import Foundation
import AVFoundation
import CoreVideo

/// Writes a single .mov streamed straight to disk with up to 1 video
/// track (hardware HEVC) and up to 2 SEPARATE AAC audio tracks
/// (microphone and system audio). Only creates tracks for the enabled
/// sources.
///
/// Thread-safety: buffers arrive from different queues (SCStream, camera,
/// microphone). AVAssetWriter is not thread-safe, so ALL appends are
/// serialized on `queue`, the only queue that touches the writer after
/// `startWriting()`. Appends are `async` (they don't block the capture
/// queues) and with `expectsMediaDataInRealTime` frames arriving while the
/// input isn't ready are simply dropped — they never pile up in RAM.
final class MovieWriter {
    struct VideoSpec {
        let width: Int
        let height: Int
        let bitrate: Int
        let fps: Int
    }

    /// The configuration's bitrate is interpreted as the target for a canvas
    /// of up to 1920×1200 (the v0.1 maximum: "Standard" stays identical).
    /// For larger canvases ("Sharp" quality, up to 4K) it scales
    /// proportionally to the pixel area — keeping the quality PER PIXEL,
    /// not recycling 1080p's 8 Mbps into a 4K frame — capped at 32 Mbps,
    /// comfortable for Apple Silicon's hardware HEVC encoder.
    static func scaledBitrate(base: Int, width: Int, height: Int) -> Int {
        let baseArea = 1920.0 * 1200.0
        let factor = max(1.0, Double(width * height) / baseArea)
        return min(Int(Double(base) * factor), 32_000_000)
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

    // MARK: Pause/resume
    // On pause, buffers stop being accepted. On resume, the exact duration
    // of the pause is accumulated into `timeOffset` (measured with the host
    // clock, the same clock that stamps all the buffers), and that offset is
    // subtracted from the PTS of every subsequent buffer: in the final file
    // the times continue with no gap or jump, even after N pauses.
    private var timeOffset = CMTime.zero
    private var pausedAtTime: CMTime?

    var isPaused: Bool {
        queue.sync { pausedAtTime != nil }
    }

    init(outputURL: URL, video: VideoSpec?, includeMicrophone: Bool, microphoneChannels: Int = 2, includeSystemAudio: Bool) throws {
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        } catch {
            throw RecordingError.writeFailed(error.localizedDescription)
        }
        hasVideoTrack = video != nil

        if let video {
            let settings: [String: Any] = [
                // HEVC: on Apple Silicon encoding goes through hardware automatically.
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
            // AVAssetWriterInput internally converts the incoming PCM to the
            // requested AAC format. The track respects the source's NATIVE
            // channels: a mono mic forced to stereo sounds quiet/lopsided.
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
            let input = makeAudioInput(channels: 2) // SCStream delivers 48 kHz stereo
            writer.add(input)
            systemAudioInput = input
        }

        guard writer.startWriting() else {
            throw RecordingError.writeFailed(writer.error?.localizedDescription ?? "startWriting failed")
        }
    }

    // MARK: - Timestamp synchronization

    /// SCStream and AVCaptureSession stamp their buffers with the SAME system
    /// clock (host clock), so it's enough to start the writer's session on
    /// the first received buffer and AVAssetWriter aligns the rest by PTS.
    ///
    /// If there is a video track, the session starts at the FIRST VIDEO FRAME
    /// and any audio arriving earlier is dropped: the microphone usually
    /// starts half a second before ScreenCaptureKit, and without this the
    /// video would open with a black stretch. Audio-only recordings start at
    /// the first audio buffer.
    private func startSessionIfNeeded(at time: CMTime, isVideo: Bool) {
        guard !sessionStarted else { return }
        if hasVideoTrack && !isVideo { return }
        writer.startSession(atSourceTime: time)
        sessionStarted = true
    }

    // MARK: - Pause

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

    // MARK: - Appends (callable from any queue)

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

    /// Copies the sample buffer with the PTS shifted by `timeOffset`.
    /// With no accumulated pauses it returns the original buffer as-is.
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

    // MARK: - Finalization

    /// Closes the file, always leaving it properly finalized and playable.
    func finish() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard !finished else {
                    continuation.resume(throwing: RecordingError.invalidState("the writer was already finalized"))
                    return
                }
                finished = true

                guard sessionStarted, writer.status == .writing else {
                    // No data arrived (or the writer failed earlier): there is
                    // nothing to save. Cancel and delete the empty file.
                    let underlying = writer.error?.localizedDescription
                    writer.cancelWriting()
                    try? FileManager.default.removeItem(at: writer.outputURL)
                    if let underlying {
                        continuation.resume(throwing: RecordingError.writeFailed(underlying))
                    } else {
                        continuation.resume(throwing: RecordingError.nothingRecorded)
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
                        continuation.resume(throwing: RecordingError.writeFailed(
                            writer.error?.localizedDescription ?? "finishWriting failed"))
                    }
                }
            }
        }
    }

    /// Aborts and deletes the file (for failures during startup).
    func cancel() {
        queue.async { [self] in
            guard !finished else { return }
            finished = true
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: writer.outputURL)
        }
    }
}
