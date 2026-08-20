import Foundation
import AVFoundation
import CoreVideo

/// Escribe un único .mov en streaming directo a disco con hasta 1 pista de
/// video (HEVC por hardware) y hasta 2 pistas de audio AAC SEPARADAS
/// (micrófono y audio del sistema). Solo crea las pistas de las fuentes
/// activadas.
///
/// Thread-safety: los buffers llegan desde colas distintas (SCStream, cámara,
/// micrófono). AVAssetWriter no es thread-safe, así que TODOS los appends se
/// serializan en `queue`, la única cola que toca el writer tras
/// `startWriting()`. Los appends son `async` (no bloquean las colas de
/// captura) y con `expectsMediaDataInRealTime` los frames que lleguen cuando
/// el input no está listo simplemente se descartan — nunca se acumulan en RAM.
final class MovieWriter {
    struct VideoSpec {
        let width: Int
        let height: Int
        let bitrate: Int
        let fps: Int
    }

    private let writer: AVAssetWriter
    private let queue = DispatchQueue(label: "record.movie-writer")

    private var videoInput: AVAssetWriterInput?
    private var pixelAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var micInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?

    private var sessionStarted = false
    private var finished = false
    private let hasVideoTrack: Bool

    // MARK: Pausa/reanudar
    // Al pausar se dejan de aceptar buffers. Al reanudar se acumula en
    // `timeOffset` la duración exacta de la pausa (medida con el host clock,
    // el mismo reloj que estampa todos los buffers), y ese offset se resta
    // del PTS de cada buffer siguiente: en el archivo final los tiempos
    // continúan sin hueco ni salto, aunque se pause N veces.
    private var timeOffset = CMTime.zero
    private var pausedAtTime: CMTime?

    var isPaused: Bool {
        queue.sync { pausedAtTime != nil }
    }

    init(outputURL: URL, video: VideoSpec?, includeMicrophone: Bool, microphoneChannels: Int = 2, includeSystemAudio: Bool) throws {
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        } catch {
            throw RecordingError.escrituraFallida(error.localizedDescription)
        }
        hasVideoTrack = video != nil

        if let video {
            let settings: [String: Any] = [
                // HEVC: en Apple Silicon la codificación va por hardware automáticamente.
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: video.width,
                AVVideoHeightKey: video.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: video.bitrate,
                    AVVideoExpectedSourceFrameRateKey: video.fps,
                ],
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            pixelAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: video.width,
                    kCVPixelBufferHeightKey as String: video.height,
                ]
            )
            writer.add(input)
            videoInput = input
        }

        func makeAudioInput(channels: Int) -> AVAssetWriterInput {
            var layout = AudioChannelLayout()
            layout.mChannelLayoutTag = channels == 1 ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: channels == 1 ? 96_000 : 160_000,
                AVChannelLayoutKey: Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size),
            ]
            // AVAssetWriterInput convierte internamente el PCM de entrada al
            // formato AAC pedido. La pista respeta los canales NATIVOS de la
            // fuente: un mic mono forzado a estéreo se escucha bajo/ladeado.
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            return input
        }

        if includeMicrophone {
            let input = makeAudioInput(channels: microphoneChannels)
            writer.add(input)
            micInput = input
        }
        if includeSystemAudio {
            let input = makeAudioInput(channels: 2) // SCStream entrega 48 kHz estéreo
            writer.add(input)
            systemAudioInput = input
        }

        guard writer.startWriting() else {
            throw RecordingError.escrituraFallida(writer.error?.localizedDescription ?? "startWriting falló")
        }
    }

    // MARK: - Sincronización de timestamps

    /// SCStream y AVCaptureSession estampan sus buffers con el MISMO reloj del
    /// sistema (host clock), así que basta con arrancar la sesión del writer en
    /// el primer buffer recibido y AVAssetWriter alinea el resto por PTS.
    ///
    /// Si hay pista de video, la sesión arranca en el PRIMER FRAME DE VIDEO y
    /// el audio que llegue antes se descarta: el micrófono suele arrancar
    /// medio segundo antes que ScreenCaptureKit, y sin esto el video empezaría
    /// con un tramo en negro. En grabaciones solo-audio arranca el primer
    /// buffer de audio.
    private func startSessionIfNeeded(at time: CMTime, isVideo: Bool) {
        guard !sessionStarted else { return }
        if hasVideoTrack && !isVideo { return }
        writer.startSession(atSourceTime: time)
        sessionStarted = true
    }

    // MARK: - Pausa

    func pause() {
        queue.async { [self] in
            guard !finished, pausedAtTime == nil else { return }
            pausedAtTime = CMClockGetTime(CMClockGetHostTimeClock())
        }
    }

    func resume() {
        queue.async { [self] in
            guard !finished, let pausedAt = pausedAtTime else { return }
            let now = CMClockGetTime(CMClockGetHostTimeClock())
            timeOffset = CMTimeAdd(timeOffset, CMTimeSubtract(now, pausedAt))
            pausedAtTime = nil
        }
    }

    // MARK: - Appends (llamables desde cualquier cola)

    func appendVideo(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        queue.async { [self] in
            guard !finished, writer.status == .writing, pausedAtTime == nil else { return }
            let adjusted = CMTimeSubtract(presentationTime, timeOffset)
            startSessionIfNeeded(at: adjusted, isVideo: true)
            guard let input = videoInput, input.isReadyForMoreMediaData else { return }
            pixelAdaptor?.append(pixelBuffer, withPresentationTime: adjusted)
        }
    }

    func appendMicrophone(_ sample: CMSampleBuffer) {
        appendAudio(sample) { self.micInput }
    }

    func appendSystemAudio(_ sample: CMSampleBuffer) {
        appendAudio(sample) { self.systemAudioInput }
    }

    private func appendAudio(_ sample: CMSampleBuffer, input: @escaping () -> AVAssetWriterInput?) {
        queue.async { [self] in
            guard !finished, writer.status == .writing, pausedAtTime == nil else { return }
            guard let retimed = retimedForOffset(sample) else { return }
            startSessionIfNeeded(at: CMSampleBufferGetPresentationTimeStamp(retimed), isVideo: false)
            guard sessionStarted, let input = input(), input.isReadyForMoreMediaData else { return }
            input.append(retimed)
        }
    }

    /// Copia el sample buffer con los PTS desplazados por `timeOffset`.
    /// Sin pausas acumuladas devuelve el buffer original tal cual.
    private func retimedForOffset(_ sample: CMSampleBuffer) -> CMSampleBuffer? {
        guard timeOffset != .zero else { return sample }
        var timingCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &timingCount)
        guard timingCount > 0 else { return sample }
        var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: timingCount)
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: timingCount, arrayToFill: &timings, entriesNeededOut: nil)
        for i in timings.indices {
            timings[i].presentationTimeStamp = CMTimeSubtract(timings[i].presentationTimeStamp, timeOffset)
            if timings[i].decodeTimeStamp.isValid {
                timings[i].decodeTimeStamp = CMTimeSubtract(timings[i].decodeTimeStamp, timeOffset)
            }
        }
        var retimed: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: nil, sampleBuffer: sample,
            sampleTimingEntryCount: timingCount, sampleTimingArray: &timings,
            sampleBufferOut: &retimed)
        return retimed
    }

    // MARK: - Finalización

    /// Cierra el archivo dejándolo siempre bien finalizado y reproducible.
    func finish() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard !finished else {
                    continuation.resume(throwing: RecordingError.estadoInvalido("el writer ya se finalizó"))
                    return
                }
                finished = true

                guard sessionStarted, writer.status == .writing else {
                    // No llegó ningún dato (o el writer falló antes): no hay
                    // nada que guardar. Cancelamos y borramos el archivo vacío.
                    let underlying = writer.error?.localizedDescription
                    writer.cancelWriting()
                    try? FileManager.default.removeItem(at: writer.outputURL)
                    if let underlying {
                        continuation.resume(throwing: RecordingError.escrituraFallida(underlying))
                    } else {
                        continuation.resume(throwing: RecordingError.nadaGrabado)
                    }
                    return
                }

                videoInput?.markAsFinished()
                micInput?.markAsFinished()
                systemAudioInput?.markAsFinished()
                writer.finishWriting { [self] in
                    if writer.status == .completed {
                        continuation.resume(returning: writer.outputURL)
                    } else {
                        continuation.resume(throwing: RecordingError.escrituraFallida(
                            writer.error?.localizedDescription ?? "finishWriting falló"))
                    }
                }
            }
        }
    }

    /// Aborta y borra el archivo (para fallos durante el arranque).
    func cancel() {
        queue.async { [self] in
            guard !finished else { return }
            finished = true
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: writer.outputURL)
        }
    }
}
