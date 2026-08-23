import Foundation
import GrabiDomain

/// Can this selection record at all, and what is missing if not?
public struct EvaluateRecordability: Sendable {
    public init() {}

    public enum Verdict: Equatable, Sendable {
        case ready
        case noSources
        case blocked([RecordingSource])
    }

    public func callAsFunction(sources: SourceSelection,
                               permissions: PermissionReport) -> Verdict {
        guard !sources.isEmpty else { return .noSources }
        let blocked = permissions.blocked(in: sources)
        return blocked.isEmpty ? .ready : .blocked(blocked)
    }
}

/// Starts a recording: checks permissions, builds the plan, hands it over.
public struct StartRecordingUseCase: Sendable {
    private let engine: CaptureEnginePort
    private let permissions: PermissionsPort
    private let clock: ClockPort

    public init(engine: CaptureEnginePort, permissions: PermissionsPort, clock: ClockPort) {
        self.engine = engine
        self.permissions = permissions
        self.clock = clock
    }

    public struct Request: Sendable {
        public var sources: SourceSelection
        public var target: CaptureTarget
        public var devices: DeviceSelection
        public var cameraLayout: CameraLayout
        public var quality: RecordingQuality
        public var destinationFolder: URL

        public init(sources: SourceSelection, target: CaptureTarget, devices: DeviceSelection,
                    cameraLayout: CameraLayout, quality: RecordingQuality, destinationFolder: URL) {
            self.sources = sources
            self.target = target
            self.devices = devices
            self.cameraLayout = cameraLayout
            self.quality = quality
            self.destinationFolder = destinationFolder
        }
    }

    /// - Returns: the sources that stand in the way, if any. Empty means the
    ///   recording started.
    public func callAsFunction(_ request: Request) async throws -> [RecordingSource] {
        guard !engine.state.isActive else { throw GrabiError.alreadyRecording }
        guard !request.sources.isEmpty else { throw GrabiError.noActiveSources }

        let report = await permissions.report(requestingAccess: true)
        let blocked = report.blocked(in: request.sources)
        guard blocked.isEmpty else { return blocked }

        let url = request.destinationFolder
            .appendingPathComponent(RecordingNaming.fileName(for: clock.now()))
        let plan = RecordingPlan.recording(
            sources: request.sources,
            target: request.target,
            devices: request.devices,
            cameraLayout: request.cameraLayout,
            quality: request.quality,
            outputURL: url)
        try await engine.startRecording(plan)
        return []
    }
}

/// Stops, and — this is the part that matters — releases every device
/// afterwards instead of leaving the recording pipeline alive for the
/// preview: the camera light must go out when the user says stop.
public struct StopRecordingUseCase: Sendable {
    private let engine: CaptureEnginePort
    private let notifier: NotifierPort

    public init(engine: CaptureEnginePort, notifier: NotifierPort) {
        self.engine = engine
        self.notifier = notifier
    }

    public func callAsFunction(elapsed: TimeInterval) async throws -> URL {
        guard engine.state.isActive else { throw GrabiError.notRecording }
        let url = try await engine.stopRecording()
        await engine.stopPreview()
        notifier.recordingFinished(url: url, duration: elapsed)
        return url
    }
}

/// Pause and resume without leaving gaps in the file.
public struct TogglePauseUseCase: Sendable {
    private let engine: CaptureEnginePort
    public init(engine: CaptureEnginePort) { self.engine = engine }

    public func callAsFunction() {
        switch engine.state {
        case .recording: engine.pause()
        case .paused: engine.resume()
        default: break
        }
    }
}
