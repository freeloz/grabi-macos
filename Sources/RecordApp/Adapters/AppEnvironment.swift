import Foundation
import GrabiCloud
import GrabiDomain
import GrabiUseCases
import RecordEngine

/// Composition root: the one place that knows which adapter satisfies which
/// port, and builds the use cases from them. Everything else depends on
/// protocols, so a test — or a future platform — swaps a line here.
@MainActor
final class AppEnvironment {
    let engine: RecordingEngine

    // Ports
    let capture: CaptureEnginePort
    let microphone: MicrophoneMonitorPort
    let permissions: PermissionsPort
    let devices: DeviceDirectoryPort
    let content: ScreenContentPort
    let library: RecordingLibraryPort
    let preferences: PreferencesPort
    let localization: LocalizationPort
    let notifier: NotifierPort
    let clock: ClockPort
    let cloud: CloudPort

    // Use cases
    let syncCapture: SyncCaptureUseCase
    let startRecording: StartRecordingUseCase
    let stopRecording: StopRecordingUseCase
    let togglePause: TogglePauseUseCase
    let refreshDevices: RefreshDevicesUseCase
    let changeLanguage: ChangeLanguageUseCase
    let listRecordings: ListRecordingsUseCase
    let deleteRecording: DeleteRecordingUseCase
    let evaluateRecordability: EvaluateRecordability
    let shareToCloud: ShareToCloudUseCase

    init(engine: RecordingEngine = RecordingEngine(),
         notifier: NotifierPort = SystemNotifier(),
         preferences: PreferencesPort = UserDefaultsPreferences()) {
        self.engine = engine
        self.capture = RecordingEngineAdapter(engine: engine)
        self.microphone = MicrophoneMonitorAdapter(engine: engine)
        self.permissions = TCCPermissions()
        self.devices = AVDeviceDirectory()
        self.content = ScreenContentAdapter()
        self.library = FileSystemLibrary()
        self.preferences = preferences
        self.localization = RuntimeLocalization()
        self.notifier = notifier
        self.clock = SystemClock()
        self.cloud = GrabiCloudAdapter()

        self.syncCapture = SyncCaptureUseCase(engine: capture, microphone: microphone)
        self.startRecording = StartRecordingUseCase(engine: capture, permissions: permissions, clock: clock)
        self.stopRecording = StopRecordingUseCase(engine: capture, notifier: notifier)
        self.togglePause = TogglePauseUseCase(engine: capture)
        self.refreshDevices = RefreshDevicesUseCase(directory: devices)
        self.changeLanguage = ChangeLanguageUseCase(localization: localization, preferences: preferences)
        self.listRecordings = ListRecordingsUseCase(library: library)
        self.deleteRecording = DeleteRecordingUseCase(library: library)
        self.evaluateRecordability = EvaluateRecordability()
        self.shareToCloud = ShareToCloudUseCase(cloud: cloud)
    }
}

/// Notifications through the app's notification manager.
struct SystemNotifier: NotifierPort {
    func recordingFinished(url: URL, duration: TimeInterval) {
        Task { @MainActor in
            NotificationManager.shared.showRecordingDone(url: url, duration: duration,
                                                         model: AppShared.model)
        }
    }
}
