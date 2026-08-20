import Foundation
import AVFoundation
import CoreVideo
@testable import RecordEngine

// Verificador de integración del motor con FUENTES SINTÉTICAS: ejercita el
// AVAssetWriter y el compositor reales (codificación HEVC/AAC incluida) sin
// necesitar permisos de pantalla/cámara/mic — corre en cualquier máquina.
//
// Uso: swift run EngineChecks   (sale con código ≠ 0 si algo falla)
//
// Los PTS sintéticos se generan con el host clock, igual que las fuentes
// reales, porque la pausa del writer mide su duración con ese reloj.

var failures = 0

func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ✓ \(message)")
    } else {
        failures += 1
        print("  ✗ FALLO: \(message)")
    }
}

func section(_ name: String) {
    print("\n\(name)")
}

// MARK: - Helpers

func makePixelBuffer(width: Int = 640, height: Int = 360) -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                        [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary,
                        &buffer)
    return buffer!
}

func makeAudioBuffer(at time: CMTime, frames: Int = 1024, channels: UInt32 = 2) -> CMSampleBuffer {
    var asbd = AudioStreamBasicDescription(
        mSampleRate: 48_000,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 4 * channels,
        mFramesPerPacket: 1,
        mBytesPerFrame: 4 * channels,
        mChannelsPerFrame: channels,
        mBitsPerChannel: 32,
        mReserved: 0)
    var format: CMAudioFormatDescription?
    CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil,
                                   magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                   formatDescriptionOut: &format)
    let dataLength = frames * Int(asbd.mBytesPerFrame)
    var block: CMBlockBuffer?
    CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: dataLength,
                                       blockAllocator: nil, customBlockSource: nil,
                                       offsetToData: 0, dataLength: dataLength,
                                       flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
    CMBlockBufferFillDataBytes(with: 0, blockBuffer: block!, offsetIntoDestination: 0, dataLength: dataLength)
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000),
                                    presentationTimeStamp: time, decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    CMSampleBufferCreate(allocator: nil, dataBuffer: block, dataReady: true,
                         makeDataReadyCallback: nil, refcon: nil,
                         formatDescription: format, sampleCount: frames,
                         sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                         sampleSizeEntryCount: 0, sampleSizeArray: nil,
                         sampleBufferOut: &sample)
    return sample!
}

func tempURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("grabi-check-\(name)-\(UUID().uuidString).mov")
}

func hostTime() -> CMTime {
    CMClockGetTime(CMClockGetHostTimeClock())
}

/// Alimenta el writer a ritmo real (~30 fps) con PTS de host clock.
func feed(writer: MovieWriter, seconds: Double, video: Bool, mic: Bool, system: Bool) async throws {
    let frames = Int(seconds * 30)
    for _ in 0..<frames {
        let now = hostTime()
        if video { writer.appendVideo(pixelBuffer: makePixelBuffer(), presentationTime: now) }
        if mic { writer.appendMicrophone(makeAudioBuffer(at: now)) }
        if system { writer.appendSystemAudio(makeAudioBuffer(at: now)) }
        try await Task.sleep(nanoseconds: 33_000_000)
    }
}

func loadAsset(_ url: URL) async throws -> (duration: Double, videoTracks: Int, audioTracks: Int) {
    let asset = AVURLAsset(url: url)
    let duration = try await asset.load(.duration).seconds
    let video = try await asset.loadTracks(withMediaType: .video).count
    let audio = try await asset.loadTracks(withMediaType: .audio).count
    return (duration, video, audio)
}

// MARK: - Checks

func checkVideoYDosAudios() async throws {
    section("1 · Video HEVC + 2 pistas de audio separadas")
    let writer = try MovieWriter(
        outputURL: tempURL("full"),
        video: .init(width: 640, height: 360, bitrate: 2_000_000, fps: 30),
        includeMicrophone: true, microphoneChannels: 1,
        includeSystemAudio: true)
    try await feed(writer: writer, seconds: 1.0, video: true, mic: true, system: true)
    let out = try await writer.finish()
    let info = try await loadAsset(out)
    check(info.videoTracks == 1, "1 pista de video (hay \(info.videoTracks))")
    check(info.audioTracks == 2, "2 pistas de audio (hay \(info.audioTracks))")
    check(abs(info.duration - 1.0) < 0.4, "duración ≈ 1 s (fue \(String(format: "%.2f", info.duration)) s)")
    try? FileManager.default.removeItem(at: out)
}

func checkPausaSinHueco() async throws {
    section("2 · Pausa/reanudar sin hueco en el archivo")
    let writer = try MovieWriter(
        outputURL: tempURL("pause"),
        video: .init(width: 640, height: 360, bitrate: 2_000_000, fps: 30),
        includeMicrophone: true, microphoneChannels: 2,
        includeSystemAudio: false)
    try await feed(writer: writer, seconds: 0.8, video: true, mic: true, system: false)
    writer.pause()
    try await Task.sleep(nanoseconds: 900_000_000) // pausa real de 0,9 s
    writer.resume()
    try await feed(writer: writer, seconds: 0.8, video: true, mic: true, system: false)
    let out = try await writer.finish()
    let info = try await loadAsset(out)
    // Sin el offset de pausa duraría ~2,5 s; con él, ~1,6 s.
    check(info.duration < 2.1, "la pausa no deja hueco (duración \(String(format: "%.2f", info.duration)) s, esperado ~1,6)")
    check(info.duration > 1.1, "no se perdió contenido (duración \(String(format: "%.2f", info.duration)) s)")
    try? FileManager.default.removeItem(at: out)
}

func checkSoloAudio() async throws {
    section("3 · Solo audio: .mov válido sin pista de video")
    let writer = try MovieWriter(
        outputURL: tempURL("audio-only"),
        video: nil,
        includeMicrophone: true, microphoneChannels: 1,
        includeSystemAudio: true)
    try await feed(writer: writer, seconds: 1.0, video: false, mic: true, system: true)
    let out = try await writer.finish()
    let info = try await loadAsset(out)
    check(info.videoTracks == 0, "0 pistas de video")
    check(info.audioTracks == 2, "2 pistas de audio (hay \(info.audioTracks))")
    check(info.duration > 0.5, "duración > 0,5 s (fue \(String(format: "%.2f", info.duration)) s)")
    try? FileManager.default.removeItem(at: out)
}

func checkNadaGrabado() async throws {
    section("4 · Detener sin datos no deja archivo a medias")
    let url = tempURL("empty")
    let writer = try MovieWriter(
        outputURL: url,
        video: .init(width: 640, height: 360, bitrate: 2_000_000, fps: 30),
        includeMicrophone: false, includeSystemAudio: false)
    do {
        _ = try await writer.finish()
        check(false, "finish debía lanzar nadaGrabado")
    } catch let error as RecordingError {
        check(error == .nadaGrabado, "lanza nadaGrabado (lanzó \(error))")
    }
    check(!FileManager.default.fileExists(atPath: url.path), "el archivo vacío se borró")
}

func checkCompositor() {
    section("5 · Compositor: formas, contentRect y layout en vivo")
    for shape in CameraShape.allCases {
        let layout = CameraLayout(shape: shape, origin: CGPoint(x: 0.7, y: 0.6), height: 0.3)
        let compositor = PiPCompositor(width: 640, height: 360, layout: layout)
        let out = compositor.compose(screen: makePixelBuffer(),
                                     camera: makePixelBuffer(width: 320, height: 240))
        check(out != nil && CVPixelBufferGetWidth(out!) == 640 && CVPixelBufferGetHeight(out!) == 360,
              "forma \(shape.rawValue): lienzo 640×360")
    }
    let compositor = PiPCompositor(width: 640, height: 360, layout: .default)
    let cropped = compositor.compose(
        screen: makePixelBuffer(),
        screenContentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
        camera: nil)
    check(cropped != nil, "recorte de contentRect (ventana que no llena el buffer)")
    compositor.layout = CameraLayout(shape: .rectangle, origin: CGPoint(x: 0.1, y: 0.1), height: 0.5)
    let live = compositor.compose(screen: makePixelBuffer(), camera: makePixelBuffer(width: 320, height: 240))
    check(live != nil, "cambio de layout en vivo")
}

func checkBitrateEscalado() {
    section("6 · Bitrate escalado por área (calidad Nítida, v0.1.1)")
    // Estándar (≤1920×1200): idéntico a v0.1, sin escalar.
    check(MovieWriter.scaledBitrate(base: 8_000_000, width: 1920, height: 1080) == 8_000_000,
          "1920×1080 → 8 Mbps (sin cambio)")
    check(MovieWriter.scaledBitrate(base: 8_000_000, width: 1920, height: 1200) == 8_000_000,
          "1920×1200 → 8 Mbps (línea base v0.1)")
    // 4K: ×3,6 el área → ×3,6 el bitrate (misma calidad por píxel).
    let uhd = MovieWriter.scaledBitrate(base: 8_000_000, width: 3840, height: 2160)
    check(abs(uhd - 28_800_000) < 100_000, "3840×2160 → ~28,8 Mbps (fue \(uhd))")
    // Tope de seguridad del encoder.
    check(MovieWriter.scaledBitrate(base: 8_000_000, width: 5120, height: 2880) == 32_000_000,
          "5K → tope 32 Mbps")
    // Ventana pequeña en Nítida: nunca por debajo de la base.
    check(MovieWriter.scaledBitrate(base: 8_000_000, width: 800, height: 600) == 8_000_000,
          "fuentes pequeñas conservan la base")
}

// MARK: - Main

print("EngineChecks · verificación de integración del motor Grabi")

do {
    try await checkVideoYDosAudios()
    try await checkPausaSinHueco()
    try await checkSoloAudio()
    try await checkNadaGrabado()
    checkCompositor()
    checkBitrateEscalado()
} catch {
    failures += 1
    print("  ✗ EXCEPCIÓN: \(error)")
}

print(failures == 0 ? "\n✅ Todo en orden (\(failures) fallos)" : "\n❌ \(failures) fallo(s)")
exit(failures == 0 ? 0 : 1)
