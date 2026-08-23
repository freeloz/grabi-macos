import Foundation
import AppKit
import GrabiDomain
import RecordEngine

/// Turns the capture engine into a `CaptureEnginePort`: the use cases speak
/// plans and states, this translates them into the engine's configuration.
/// Swapping ScreenCaptureKit for something else means rewriting this file
/// and nothing above it.
final class RecordingEngineAdapter: CaptureEnginePort, @unchecked Sendable {
    private let engine: RecordingEngine

    init(engine: RecordingEngine) { self.engine = engine }

    var state: RecordingState { engine.state }
    var isPreviewing: Bool { engine.isPreviewing }

    func startPreview(_ plan: RecordingPlan) async throws {
        try await engine.startPreview(configuration: Self.configuration(from: plan, outputURL: nil))
    }

    func stopPreview() async {
        await engine.stopPreview()
    }

    func startRecording(_ plan: RecordingPlan) async throws {
        guard let url = plan.outputURL else { throw GrabiError.engineFailure("a recording needs a file") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try await engine.start(configuration: Self.configuration(from: plan, outputURL: url))
    }

    func stopRecording() async throws -> URL {
        try await engine.stop()
    }

    func pause() { engine.pause() }
    func resume() { engine.resume() }
    func update(cameraLayout: CameraLayout) { engine.updateCameraLayout(cameraLayout) }
    func setMicrophoneMuted(_ muted: Bool) { engine.setMicrophoneMuted(muted) }
    func setCameraHidden(_ hidden: Bool) async { await engine.setCameraHidden(hidden) }

    private static func configuration(from plan: RecordingPlan, outputURL: URL?) -> RecordingConfiguration {
        RecordingConfiguration(
            capturesScreen: plan.sources.screen,
            capturesCamera: plan.sources.camera,
            capturesMicrophone: plan.sources.microphone,
            capturesSystemAudio: plan.sources.systemAudio,
            // A preview writes nothing; the engine still wants a URL for its
            // configuration, so it gets a throwaway one it never opens.
            outputURL: outputURL ?? URL(fileURLWithPath: "/dev/null"),
            targetWidth: plan.targetWidth,
            framesPerSecond: plan.framesPerSecond,
            target: plan.target,
            cameraLayout: plan.cameraLayout,
            cameraDeviceID: plan.devices.cameraID,
            microphoneDeviceID: plan.devices.microphoneID)
    }
}

/// The microphone level session, separate from the recording pipeline.
final class MicrophoneMonitorAdapter: MicrophoneMonitorPort, @unchecked Sendable {
    private let engine: RecordingEngine

    init(engine: RecordingEngine) { self.engine = engine }

    func start(deviceID: String?) async { await engine.startMicrophoneMonitoring(deviceID: deviceID) }
    func stop() async { await engine.stopMicrophoneMonitoring() }
}

/// Permissions and the panes that fix them.
struct TCCPermissions: PermissionsPort {
    func report(requestingAccess: Bool) async -> PermissionReport {
        await RecordingEngine.preflight(requestingAccess: requestingAccess)
    }

    /// The exact pane that fixes each source — anything else makes people
    /// hunt through System Settings.
    func openSystemSettings(for source: RecordingSource) {
        let anchor: String
        switch source {
        case .screen, .systemAudio: anchor = "Privacy_ScreenCapture"
        case .camera: anchor = "Privacy_Camera"
        case .microphone: anchor = "Privacy_Microphone"
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Displays and windows available to capture.
struct ScreenContentAdapter: ScreenContentPort {
    func availableContent() async throws -> ShareableContent {
        try await RecordingEngine.availableContent()
    }
}

/// The system clock. Injected so a test can pin the file name.
struct SystemClock: ClockPort {
    func now() -> Date { Date() }
}
