// @testable only exists in debug builds; in release (make-app.sh) this
// executable reduces to a notice so packaging doesn't break.
#if DEBUG
import Foundation
import AVFoundation
import CoreVideo
import GrabiDomain
@testable import RecordEngine

// Engine integration checker with SYNTHETIC SOURCES: exercises the real
// AVAssetWriter and compositor (HEVC/AAC encoding included) without
// needing screen/camera/mic permissions — runs on any machine.
//
// Usage: swift run EngineChecks   (exits with code ≠ 0 if anything fails)
//
// Synthetic PTS are generated with the host clock, just like the real
// sources, because the writer's pause measures its duration with that clock.

var failures = 0

func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ✓ \(message)")
    } else {
        failures += 1
        print("  ✗ FAIL: \(message)")
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

/// Feeds the writer at real-time pace (~30 fps) with host-clock PTS.
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
    section("1 · HEVC video + 2 separate audio tracks")
    let writer = try MovieWriter(
        outputURL: tempURL("full"),
        video: .init(width: 640, height: 360, bitrate: 2_000_000, fps: 30),
        includeMicrophone: true, microphoneChannels: 1,
        includeSystemAudio: true)
    try await feed(writer: writer, seconds: 1.0, video: true, mic: true, system: true)
    let out = try await writer.finish()
    let info = try await loadAsset(out)
    check(info.videoTracks == 1, "1 video track (got \(info.videoTracks))")
    check(info.audioTracks == 2, "2 audio tracks (got \(info.audioTracks))")
    check(abs(info.duration - 1.0) < 0.4, "duration ≈ 1 s (was \(String(format: "%.2f", info.duration)) s)")
    try? FileManager.default.removeItem(at: out)
}

func checkPausaSinHueco() async throws {
    section("2 · Pause/resume without a gap in the file")
    let writer = try MovieWriter(
        outputURL: tempURL("pause"),
        video: .init(width: 640, height: 360, bitrate: 2_000_000, fps: 30),
        includeMicrophone: true, microphoneChannels: 2,
        includeSystemAudio: false)
    try await feed(writer: writer, seconds: 0.8, video: true, mic: true, system: false)
    writer.pause()
    try await Task.sleep(nanoseconds: 900_000_000) // real 0.9 s pause
    writer.resume()
    try await feed(writer: writer, seconds: 0.8, video: true, mic: true, system: false)
    let out = try await writer.finish()
    let info = try await loadAsset(out)
    // Without the pause offset it would last ~2.5 s; with it, ~1.6 s.
    check(info.duration < 2.1, "the pause leaves no gap (duration \(String(format: "%.2f", info.duration)) s, expected ~1.6)")
    check(info.duration > 1.1, "no content was lost (duration \(String(format: "%.2f", info.duration)) s)")
    try? FileManager.default.removeItem(at: out)
}

func checkSoloAudio() async throws {
    section("3 · Audio only: valid .mov with no video track")
    let writer = try MovieWriter(
        outputURL: tempURL("audio-only"),
        video: nil,
        includeMicrophone: true, microphoneChannels: 1,
        includeSystemAudio: true)
    try await feed(writer: writer, seconds: 1.0, video: false, mic: true, system: true)
    let out = try await writer.finish()
    let info = try await loadAsset(out)
    check(info.videoTracks == 0, "0 video tracks")
    check(info.audioTracks == 2, "2 audio tracks (got \(info.audioTracks))")
    check(info.duration > 0.5, "duration > 0.5 s (was \(String(format: "%.2f", info.duration)) s)")
    try? FileManager.default.removeItem(at: out)
}

func checkNadaGrabado() async throws {
    section("4 · Stopping with no data leaves no half-written file")
    let url = tempURL("empty")
    let writer = try MovieWriter(
        outputURL: url,
        video: .init(width: 640, height: 360, bitrate: 2_000_000, fps: 30),
        includeMicrophone: false, includeSystemAudio: false)
    do {
        _ = try await writer.finish()
        check(false, "finish should have thrown nothingRecorded")
    } catch let error as RecordingError {
        check(error == .nothingRecorded, "throws nothingRecorded (threw \(error))")
    }
    check(!FileManager.default.fileExists(atPath: url.path), "the empty file was deleted")
}

func checkCompositor() {
    section("5 · Compositor: shapes, contentRect and live layout")
    for shape in CameraShape.allCases {
        let layout = CameraLayout(shape: shape, origin: CGPoint(x: 0.7, y: 0.6), height: 0.3)
        let compositor = PiPCompositor(width: 640, height: 360, layout: layout)
        let out = compositor.compose(screen: makePixelBuffer(),
                                     camera: makePixelBuffer(width: 320, height: 240))
        check(out != nil && CVPixelBufferGetWidth(out!) == 640 && CVPixelBufferGetHeight(out!) == 360,
              "shape \(shape.rawValue): 640×360 canvas")
    }
    let compositor = PiPCompositor(width: 640, height: 360, layout: .default)
    let cropped = compositor.compose(
        screen: makePixelBuffer(),
        screenContentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
        camera: nil)
    check(cropped != nil, "contentRect crop (window that doesn't fill the buffer)")
    compositor.layout = CameraLayout(shape: .rectangle, origin: CGPoint(x: 0.1, y: 0.1), height: 0.5)
    let live = compositor.compose(screen: makePixelBuffer(), camera: makePixelBuffer(width: 320, height: 240))
    check(live != nil, "live layout change")
}

func checkBitrateEscalado() {
    section("6 · Bitrate scaled by area (Sharp quality, v0.1.1)")
    // Standard (≤1920×1200): identical to v0.1, no scaling.
    check(MovieWriter.scaledBitrate(base: 8_000_000, width: 1920, height: 1080) == 8_000_000,
          "1920×1080 → 8 Mbps (unchanged)")
    check(MovieWriter.scaledBitrate(base: 8_000_000, width: 1920, height: 1200) == 8_000_000,
          "1920×1200 → 8 Mbps (v0.1 baseline)")
    // 4K: ×3.6 the area → ×3.6 the bitrate (same quality per pixel).
    let uhd = MovieWriter.scaledBitrate(base: 8_000_000, width: 3840, height: 2160)
    check(abs(uhd - 28_800_000) < 100_000, "3840×2160 → ~28.8 Mbps (was \(uhd))")
    // Encoder safety cap.
    check(MovieWriter.scaledBitrate(base: 8_000_000, width: 5120, height: 2880) == 32_000_000,
          "5K → 32 Mbps cap")
    // Small window on Sharp: never below the base.
    check(MovieWriter.scaledBitrate(base: 8_000_000, width: 800, height: 600) == 8_000_000,
          "small sources keep the base")
}

// MARK: - Main

print("EngineChecks · Grabi engine integration check")

do {
    try await checkVideoYDosAudios()
    try await checkPausaSinHueco()
    try await checkSoloAudio()
    try await checkNadaGrabado()
    checkCompositor()
    checkBitrateEscalado()
} catch {
    failures += 1
    print("  ✗ EXCEPTION: \(error)")
}

print(failures == 0 ? "\n✅ All good (\(failures) failures)" : "\n❌ \(failures) failure(s)")
exit(failures == 0 ? 0 : 1)

#else
print("EngineChecks runs in debug: use `swift run EngineChecks` (without -c release)")
#endif
