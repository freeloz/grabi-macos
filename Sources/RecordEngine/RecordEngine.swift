import Foundation
import AVFoundation
import CoreVideo
import Combine

/// Observable states of the engine.
public enum RecordingState: Equatable {
    case idle
    case starting
    case recording
    case paused
    case stopping
    case stopped(URL)
    case failed(RecordingError)

    public var isActive: Bool {
        switch self {
        case .starting, .recording, .paused, .stopping: return true
        default: return false
        }
    }
}

/// Public facade of the recording engine.
///
/// Flow: `Preflight.check()` → (optional) `startPreview(configuration:)`
/// to see the composed canvas live → `start(configuration:)` →
/// `pause()`/`resume()` → `stop()`. The preview and the recording share
/// the same capture pipeline: starting the recording with the same
/// configuration restarts no cameras or streams.
public final class RecordingEngine: ObservableObject {
    @Published public private(set) var state: RecordingState = .idle
    /// true while the pipeline emits preview frames.
    @Published public private(set) var isPreviewing = false

    /// Composed frames (screen+camera exactly as recorded), BGRA.
    /// Invoked on a capture queue: the UI must hop to main if it touches views.
    public var onPreviewFrame: ((CVPixelBuffer) -> Void)? {
        didSet { pipeline?.onPreviewFrame = onPreviewFrame }
    }

    /// Raw camera frames (for the floating selfie box).
    public var onCameraFrame: ((CVPixelBuffer) -> Void)? {
        didSet { pipeline?.onCameraFrame = onCameraFrame }
    }

    /// Microphone level 0–1 (during monitoring or recording). Capture queue.
    public var onMicLevel: ((Double) -> Void)?
    /// System audio level 0–1 (while the pipeline is active). Capture queue.
    public var onSystemAudioLevel: ((Double) -> Void)?

    private var pipeline: CapturePipeline?
    private var micCapturer: MicrophoneCapturer?
    private var micMonitor: MicrophoneCapturer?
    private var writer: MovieWriter?

    // Live microphone mute: real SILENCE is written (zeroed buffers)
    // instead of leaving a gap — the track stays continuous and in sync.
    private let muteLock = NSLock()
    private var _micMuted = false
    private var isMicrophoneMuted: Bool {
        muteLock.lock(); defer { muteLock.unlock() }; return _micMuted
    }

    public func setMicrophoneMuted(_ muted: Bool) {
        muteLock.lock(); _micMuted = muted; muteLock.unlock()
        if muted { onMicLevel?(0) }
    }

    /// Turns the camera off/on during recording (PiP mode only).
    public func setCameraHidden(_ hidden: Bool) async {
        await pipeline?.setCameraHidden(hidden)
    }

    public init() {}

    // MARK: - Discovery

    /// Preflight check: which sources are available and permitted.
    public static func preflight(requestingAccess: Bool = true) async -> PreflightReport {
        await Preflight.check(requestingAccess: requestingAccess)
    }

    /// Displays and windows available for capture.
    public static func availableContent() async throws -> ShareableContent {
        try await ShareableContent.current()
    }

    // MARK: - Microphone level monitoring (feedback before recording)

    /// Captures the mic ONLY to measure its level (records nothing). Lights
    /// up the system's orange indicator — honesty above all. It turns off by
    /// itself when recording starts (the recording already reports the level
    /// through its own capture).
    public func startMicrophoneMonitoring(deviceID: String? = nil) async {
        guard micMonitor == nil, micCapturer == nil else { return }
        let monitor = MicrophoneCapturer()
        guard (try? monitor.configure(deviceID: deviceID)) != nil else { return }
        monitor.onAudio = { [weak self] sample in
            if let level = AudioLevel.normalizedLevel(from: sample) {
                self?.onMicLevel?(level)
            }
        }
        micMonitor = monitor
        await monitor.start()
    }

    public func stopMicrophoneMonitoring() async {
        await micMonitor?.stop()
        micMonitor = nil
        onMicLevel?(0)
    }

    // MARK: - Preview

    /// Starts the capture pipeline without writing to disk. The UI receives
    /// the frames via `onPreviewFrame`. If a preview with a different
    /// configuration is already running, it restarts with the new one.
    public func startPreview(configuration config: RecordingConfiguration) async throws {
        guard !state.isActive else {
            throw RecordingError.invalidState("the preview cannot be changed during a recording")
        }
        if let pipeline, pipeline.isCompatible(with: config) {
            pipeline.updateCameraLayout(config.cameraLayout)
            setPreviewing(true)
            return
        }
        await teardownPipeline()
        guard config.hasVideo else { return } // without video there is nothing to preview
        let pipeline = CapturePipeline(config: config)
        pipeline.onPreviewFrame = onPreviewFrame
        pipeline.onCameraFrame = onCameraFrame
        pipeline.onSystemAudioLevel = { [weak self] level in
            self?.onSystemAudioLevel?(level)
        }
        pipeline.onFatalError = { [weak self] error in
            Task { [weak self] in await self?.handleFatalError(error) }
        }
        do {
            try await pipeline.start()
        } catch {
            await pipeline.stop()
            throw (error as? RecordingError) ?? .captureInterrupted(error.localizedDescription)
        }
        self.pipeline = pipeline
        setPreviewing(true)
    }

    /// Stops the preview (if not recording, shuts down the capture).
    public func stopPreview() async {
        setPreviewing(false)
        guard !state.isActive else { return } // the pipeline goes on: it's recording
        await teardownPipeline()
    }

    /// Changes the camera's shape/position/size LIVE (preview and recording).
    public func updateCameraLayout(_ layout: CameraLayout) {
        pipeline?.updateCameraLayout(layout)
    }

    // MARK: - Recording

    public func start(configuration config: RecordingConfiguration) async throws {
        guard !state.isActive else {
            throw RecordingError.invalidState("a recording is already in progress")
        }
        guard config.hasAnySource else {
            throw RecordingError.noActiveSources
        }
        setState(.starting)

        do {
            try await startRecordingPipeline(config: config)
            setState(.recording)
        } catch {
            // Full cleanup: nothing may stay running, no half-written files
            // (except the preview, which is kept if it was active).
            await stopMic()
            writer?.cancel()
            writer = nil
            if !isPreviewing { await teardownPipeline() }
            let recError = (error as? RecordingError) ?? .captureInterrupted(error.localizedDescription)
            setState(.failed(recError))
            throw recError
        }
    }

    private func startRecordingPipeline(config: RecordingConfiguration) async throws {
        // Re-validate permissions right before starting: never fail
        // mid-recording over something detectable now.
        let report = await Preflight.check(requestingAccess: true)
        if config.capturesScreen || config.capturesSystemAudio {
            guard report.screen.isUsable else { throw RecordingError.screenPermissionDenied }
        }
        if config.capturesCamera {
            switch report.camera {
            case .available: break
            case .permissionDenied: throw RecordingError.cameraPermissionDenied
            case .unavailable: throw RecordingError.cameraUnavailable
            }
        }
        if config.capturesMicrophone {
            switch report.microphone {
            case .available: break
            case .permissionDenied: throw RecordingError.microphonePermissionDenied
            case .unavailable: throw RecordingError.microphoneUnavailable
            }
        }

        // Pipeline: reuse the preview's if compatible (the capture is
        // already running); otherwise, build a new one.
        let pipeline: CapturePipeline
        if let existing = self.pipeline, existing.isCompatible(with: config) {
            pipeline = existing
            pipeline.updateCameraLayout(config.cameraLayout)
        } else {
            await teardownPipeline()
            pipeline = CapturePipeline(config: config)
            pipeline.onPreviewFrame = onPreviewFrame
            pipeline.onCameraFrame = onCameraFrame
            pipeline.onSystemAudioLevel = { [weak self] level in
                self?.onSystemAudioLevel?(level)
            }
            pipeline.onFatalError = { [weak self] error in
                Task { [weak self] in await self?.handleFatalError(error) }
            }
            try await pipeline.start()
            self.pipeline = pipeline
        }

        // Level monitoring hands the mic over to the recording.
        await stopMicrophoneMonitoring()

        // Microphone: configured first (without starting) to learn its
        // native channels; it only captures during the recording.
        var mic: MicrophoneCapturer?
        if config.capturesMicrophone {
            let m = MicrophoneCapturer()
            try m.configure(deviceID: config.microphoneDeviceID)
            mic = m
        }

        // Writer with ONLY the tracks of the enabled sources.
        var videoSpec: MovieWriter.VideoSpec?
        if let size = pipeline.canvasSize, config.hasVideo {
            videoSpec = .init(
                width: size.width, height: size.height,
                bitrate: MovieWriter.scaledBitrate(base: config.videoBitrate,
                                                   width: size.width, height: size.height),
                fps: config.framesPerSecond)
        }
        let writer = try MovieWriter(
            outputURL: config.outputURL,
            video: videoSpec,
            includeMicrophone: config.capturesMicrophone,
            microphoneChannels: mic?.nativeChannelCount ?? 2,
            includeSystemAudio: config.capturesSystemAudio)

        setMicrophoneMuted(false) // every recording starts unmuted
        if let mic {
            mic.onAudio = { [weak self] sample in
                guard let self else { return }
                if self.isMicrophoneMuted, let block = CMSampleBufferGetDataBuffer(sample) {
                    CMBlockBufferFillDataBytes(with: 0, blockBuffer: block,
                                               offsetIntoDestination: 0,
                                               dataLength: CMBlockBufferGetDataLength(block))
                }
                writer.appendMicrophone(sample)
                if let level = AudioLevel.normalizedLevel(from: sample) {
                    self.onMicLevel?(level)
                }
            }
            micCapturer = mic
            await mic.start()
        }

        self.writer = writer
        pipeline.attachWriter(writer)
    }

    // MARK: - Pause

    public func pause() {
        guard case .recording = state else { return }
        writer?.pause()
        setState(.paused)
    }

    public func resume() {
        guard case .paused = state else { return }
        writer?.resume()
        setState(.recording)
    }

    // MARK: - Stop

    /// Stops the recording and returns the URL of the finalized file.
    /// The preview (if it was active) keeps running.
    @discardableResult
    public func stop() async throws -> URL {
        switch state {
        case .recording, .paused: break
        default: throw RecordingError.invalidState("no recording is in progress")
        }
        setState(.stopping)

        // Order: first buffers stop reaching the writer, then it gets
        // finalized — that way the file is always playable.
        pipeline?.detachWriter()
        await stopMic()
        if !isPreviewing {
            await teardownPipeline()
        }

        guard let writer else {
            setState(.failed(.invalidState("there was no active writer")))
            throw RecordingError.invalidState("there was no active writer")
        }
        self.writer = nil
        do {
            let url = try await writer.finish()
            setState(.stopped(url))
            return url
        } catch {
            let recError = (error as? RecordingError) ?? .writeFailed(error.localizedDescription)
            setState(.failed(recError))
            throw recError
        }
    }

    // MARK: - Internal

    private func handleFatalError(_ error: Error) async {
        switch state {
        case .recording, .paused:
            setState(.stopping)
            await stopMic()
            await teardownPipeline()
            setPreviewing(false)
            // Try to save what was recorded so far: the file gets finalized.
            if let writer {
                self.writer = nil
                _ = try? await writer.finish()
            }
            setState(.failed(.captureInterrupted(error.localizedDescription)))
        default:
            // The preview failed (no recording): shut down silently.
            await teardownPipeline()
            setPreviewing(false)
        }
    }

    private func stopMic() async {
        await micCapturer?.stop()
        micCapturer = nil
    }

    private func teardownPipeline() async {
        await pipeline?.stop()
        pipeline = nil
    }

    private func setState(_ newState: RecordingState) {
        if Thread.isMainThread {
            state = newState
        } else {
            DispatchQueue.main.sync { self.state = newState }
        }
    }

    private func setPreviewing(_ value: Bool) {
        if Thread.isMainThread {
            isPreviewing = value
        } else {
            DispatchQueue.main.sync { self.isPreviewing = value }
        }
    }
}
