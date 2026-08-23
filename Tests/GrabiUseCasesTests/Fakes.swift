import Foundation
@testable import GrabiDomain
@testable import GrabiUseCases

/// In-memory stand-ins for every port. They record what was asked of them so
/// a test can assert on behavior instead of on implementation details.
final class FakeEngine: CaptureEnginePort, @unchecked Sendable {
    var state: RecordingState = .idle
    var isPreviewing = false

    private(set) var previewPlans: [RecordingPlan] = []
    private(set) var recordingPlans: [RecordingPlan] = []
    private(set) var stopPreviewCalls = 0
    private(set) var pauseCalls = 0
    private(set) var resumeCalls = 0
    var stopResult = URL(fileURLWithPath: "/tmp/recording.mov")
    var startRecordingError: Error?

    func startPreview(_ plan: RecordingPlan) async throws {
        previewPlans.append(plan)
        isPreviewing = true
    }
    func stopPreview() async {
        stopPreviewCalls += 1
        isPreviewing = false
    }
    func startRecording(_ plan: RecordingPlan) async throws {
        if let startRecordingError { throw startRecordingError }
        recordingPlans.append(plan)
        state = .recording
    }
    func stopRecording() async throws -> URL {
        state = .stopped(stopResult)
        return stopResult
    }
    func pause() { pauseCalls += 1; state = .paused }
    func resume() { resumeCalls += 1; state = .recording }
    func update(cameraLayout: CameraLayout) {}
    func setMicrophoneMuted(_ muted: Bool) {}
    func setCameraHidden(_ hidden: Bool) async {}
}

final class FakeMicrophoneMonitor: MicrophoneMonitorPort, @unchecked Sendable {
    private(set) var starts: [String?] = []
    private(set) var stops = 0
    var isRunning: Bool { starts.count > stops }
    func start(deviceID: String?) async { starts.append(deviceID) }
    func stop() async { stops += 1 }
}

struct FakePermissions: PermissionsPort, @unchecked Sendable {
    var reportToReturn: PermissionReport = .allAvailable
    final class Calls: @unchecked Sendable { var requestedAccess: [Bool] = []; var opened: [RecordingSource] = [] }
    let calls = Calls()

    func report(requestingAccess: Bool) async -> PermissionReport {
        calls.requestedAccess.append(requestingAccess)
        return reportToReturn
    }
    func openSystemSettings(for source: RecordingSource) { calls.opened.append(source) }
}

struct FakeDeviceDirectory: DeviceDirectoryPort, @unchecked Sendable {
    var camerasToReturn: [CaptureDeviceInfo] = []
    var microphonesToReturn: [CaptureDeviceInfo] = []
    func cameras() -> [CaptureDeviceInfo] { camerasToReturn }
    func microphones() -> [CaptureDeviceInfo] { microphonesToReturn }
}

final class FakeNotifier: NotifierPort, @unchecked Sendable {
    private(set) var finished: [(URL, TimeInterval)] = []
    func recordingFinished(url: URL, duration: TimeInterval) { finished.append((url, duration)) }
}

struct FixedClock: ClockPort, Sendable {
    let date: Date
    func now() -> Date { date }
}

final class FakeLibrary: RecordingLibraryPort, @unchecked Sendable {
    var stored: [Recording] = []
    private(set) var trashed: [Recording] = []
    var trashError: Error?

    func recordings(in folder: URL) -> [Recording] { stored }
    func duration(of recording: Recording) async -> TimeInterval? { recording.duration }
    func moveToTrash(_ recording: Recording) throws {
        if let trashError { throw trashError }
        trashed.append(recording)
        stored.removeAll { $0.id == recording.id }
    }
    func reveal(_ recording: Recording) {}
    func play(_ recording: Recording) {}
    func copyToPasteboard(_ recording: Recording) {}
}

final class FakePreferences: PreferencesPort, @unchecked Sendable {
    var destinationFolder = URL(fileURLWithPath: "/tmp/Grabi")
    var quality: RecordingQuality = .standard
    var cameraLayout: CameraLayout = .default
    var devices = DeviceSelection()
    var language: AppLanguage = .system
    var quickAccessEnabled = true
    var onboardingDone = false
}

final class FakeLocalization: LocalizationPort, @unchecked Sendable {
    private(set) var applied: [AppLanguage] = []
    func apply(_ language: AppLanguage) { applied.append(language) }
}
