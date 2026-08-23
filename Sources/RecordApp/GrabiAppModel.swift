import Foundation
import AppKit
import Combine
import AVFoundation
import RecordEngine
import RecordUI
import GrabiDomain
import GrabiUseCases

/// Display names live with the strings that back them: the domain types
/// themselves stay free of localization.
extension RecordingQuality {
    var displayName: String {
        switch self {
        case .standard: return L("app.quality.standard")
        case .sharp: return L("app.quality.sharp")
        }
    }

    /// Honest hint about the cost (measured: ~2.9 GB/h at 1080p with moving
    /// content; sharp depends on the source).
    var hint: String {
        switch self {
        case .standard: return L("app.quality.standard.hint")
        case .sharp: return L("app.quality.sharp.hint")
        }
    }
}

@MainActor
final class GrabiAppModel: ObservableObject {
    /// Composition root: ports and use cases. The model coordinates the
    /// screens; the policy lives in the use cases, where it is tested.
    let environment: AppEnvironment
    var engine: RecordingEngine { environment.engine }

    /// The current selection as a value the use cases understand.
    var sourceSelection: SourceSelection {
        SourceSelection(screen: screenEnabled, camera: cameraEnabled,
                        microphone: micEnabled, systemAudio: systemAudioEnabled)
    }

    var deviceSelection: DeviceSelection {
        DeviceSelection(cameraID: cameraDeviceID, microphoneID: microphoneDeviceID)
    }

    // MARK: Sources
    @Published var screenEnabled = true { didSet { sourcesChanged() } }
    @Published var cameraEnabled = true { didSet { sourcesChanged() } }
    @Published var micEnabled = true { didSet { sourcesChanged() } }
    @Published var systemAudioEnabled = true { didSet { sourcesChanged() } }

    @Published private(set) var preflight: PermissionReport?
    @Published private(set) var celebrating: Set<RecordingSource> = []

    // MARK: Capture
    @Published var captureMode: CaptureMode = .screen { didSet { sourcesChanged() } }
    @Published private(set) var availableDisplays: [DisplayInfo] = []
    @Published private(set) var availableWindows: [WindowInfo] = []
    @Published var selectedDisplayID: CGDirectDisplayID? { didSet { sourcesChanged() } }
    @Published var selectedWindow: WindowInfo? { didSet { sourcesChanged() } }
    @Published var regionRect: CGRect? { didSet { sourcesChanged() } }

    // MARK: Camera (persisted across sessions)
    @Published var cameraLayout: CameraLayout = .default {
        didSet {
            environment.capture.update(cameraLayout: cameraLayout)
            environment.preferences.cameraLayout = cameraLayout
        }
    }

    // MARK: Recording state
    @Published private(set) var engineState: RecordingState = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var countdown: Int?
    @Published var errorMessage: String?
    @Published private(set) var lastRecordingURL: URL?
    /// Levels live in their own object: they change dozens of times a
    /// second and must not re-render the window with them.
    let levels = AudioLevels()
    @Published var showUnavailableDialog = false
    @Published private(set) var unavailableSources: [RecordingSource] = []
    /// Live controls during recording (floating pill).
    @Published private(set) var micMuted = false
    @Published private(set) var cameraHidden = false

    // MARK: Preferences
    @Published var destinationFolder: URL {
        didSet {
            environment.preferences.destinationFolder = destinationFolder
            refreshLibrary()
        }
    }
    /// Chosen camera / microphone (nil = whatever macOS picks). People
    /// record with external webcams and USB mics, not only the built-in ones.
    @Published var cameraDeviceID: String? {
        didSet {
            environment.preferences.devices = deviceSelection
            sourcesChanged()
        }
    }
    @Published var microphoneDeviceID: String? {
        didSet {
            environment.preferences.devices = deviceSelection
            restartMicMonitoringIfNeeded()
        }
    }
    @Published private(set) var availableCameras: [CaptureDeviceInfo] = []
    @Published private(set) var availableMicrophones: [CaptureDeviceInfo] = []

    /// In-app language: Grabi can speak a different language than the Mac.
    @Published var language: AppLanguage {
        didSet {
            environment.changeLanguage(language)
            objectWillChange.send() // every visible string is re-read
        }
    }

    /// Menu bar item: quick access without opening the window (Phase 6).
    @Published var quickAccessEnabled: Bool {
        didSet { environment.preferences.quickAccessEnabled = quickAccessEnabled }
    }
    @Published var onboardingDone: Bool {
        didSet { environment.preferences.onboardingDone = onboardingDone }
    }
    @Published var quality: RecordingQuality {
        didSet {
            environment.preferences.quality = quality
            sourcesChanged() // the preview restarts at the new resolution
        }
    }

    /// The recordings library (the destination folder's real contents).
    let library = LibraryStore()

    // Managed windows
    let mainWindow = MainWindowController()
    let pillController = PillWindowController()
    let cameraWindowController = CameraWindowController()
    let countdownController = CountdownWindowController()
    let onboardingController = OnboardingWindowController()
    let settingsController = SettingsWindowController()
    let regionController = RegionPickerController()
    let capturePickerController = WindowPickerController()
    let borderController = CaptureBorderWindowController()
    let permissionController = PermissionWindowController()

    private let hotkeys = HotkeyManager()
    private var cancellables = Set<AnyCancellable>()
    private var timer: AnyCancellable?
    private var segmentStart: Date?
    private var accumulated: TimeInterval = 0
    private var micMonitoringWanted = false
    private var panelIsOpen = false
    /// Exposed for the lifecycle self-check.
    var isMonitoringMic: Bool { micMonitoringWanted }

    var isRecording: Bool { engineState == .recording }
    var isPaused: Bool { engineState == .paused }
    var isActive: Bool { engineState.isActive }

    var anySourceEnabled: Bool {
        screenEnabled || cameraEnabled || micEnabled || systemAudioEnabled
    }

    convenience init() {
        self.init(environment: AppEnvironment())
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        let preferences = environment.preferences
        destinationFolder = preferences.destinationFolder
        onboardingDone = preferences.onboardingDone
        quickAccessEnabled = preferences.quickAccessEnabled
        let storedDevices = preferences.devices
        cameraDeviceID = storedDevices.cameraID
        microphoneDeviceID = storedDevices.microphoneID
        let storedLanguage = preferences.language
        language = storedLanguage
        quality = preferences.quality
        cameraLayout = preferences.cameraLayout
        environment.localization.apply(storedLanguage)

        engine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.engineStateChanged(state) }
            .store(in: &cancellables)

        // One preview stream, delivered to whichever surface is on screen.
        engine.onPreviewFrame = { [weak self] pixelBuffer in
            DispatchQueue.main.async { self?.mainWindow.receive(pixelBuffer) }
        }

        engine.onMicLevel = { [weak self] level in
            Task { @MainActor in self?.levels.report(microphone: level) }
        }
        engine.onSystemAudioLevel = { [weak self] level in
            Task { @MainActor in self?.levels.report(system: level) }
        }

        // Global shortcuts: ⌘⇧2 record/stop · ⌘⇧P pause/resume.
        hotkeys.onToggleRecord = { [weak self] in
            Task { @MainActor in self?.toggleRecording() }
        }
        hotkeys.onTogglePause = { [weak self] in
            Task { @MainActor in self?.togglePause() }
        }
        hotkeys.register()

        NotificationManager.shared.configure(model: self)

        // On returning from System Settings, re-check permissions and
        // celebrate the newly granted ones (Phase 3 §04).
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshAll() }
        }

        Task { await refreshAll(applyDefaults: true) }
        refreshLibrary()
    }

    // MARK: - Main window (Phase 6)

    func showMainWindow(tab: MainTab? = nil) {
        mainWindow.show(model: self, tab: tab)
    }

    func mainWindowShown() {
        refreshLibrary()
        updateCapture()
    }

    func mainWindowClosed() {
        // Closing the window must never stop a recording: only the preview.
        updateCapture()
    }

    /// The in-window welcome is done (permissions granted or postponed).
    func finishWelcome(startRecording: Bool) {
        onboardingDone = true
        Task {
            await refreshAll(applyDefaults: true)
            updateCapture()
            if startRecording { requestStart() }
        }
    }

    func refreshLibrary() {
        library.refresh(folder: destinationFolder)
    }

    // MARK: - Status shown by the mascot in the sidebar

    var statusPose: MascotPose {
        if isActive { return .recording }
        if !anySourceEnabled { return .worried }
        if let report = preflight, enabledSources.contains(where: { !report.status(for: $0).isUsable }) {
            return .worried
        }
        return .ready
    }

    var statusMessage: String {
        if isActive { return L("app.status.recording") }
        if !anySourceEnabled { return L("app.status.noSources") }
        if let report = preflight, enabledSources.contains(where: { !report.status(for: $0).isUsable }) {
            return L("app.status.permissions")
        }
        return L("app.status.ready")
    }

    var recordButtonState: RecordButtonState {
        switch engineState {
        case .recording, .starting, .stopping: return .recording
        case .paused: return .paused
        default: return .ready
        }
    }

    private var enabledSources: [RecordingSource] {
        var list: [RecordingSource] = []
        if screenEnabled { list.append(.screen) }
        if cameraEnabled { list.append(.camera) }
        if micEnabled { list.append(.microphone) }
        if systemAudioEnabled { list.append(.systemAudio) }
        return list
    }

    // MARK: - Preflight and content

    func refreshAll(applyDefaults: Bool = false) async {
        let old = preflight
        let report = await RecordingEngine.preflight(requestingAccess: false)
        preflight = report

        if applyDefaults {
            screenEnabled = report.screen.isUsable
            cameraEnabled = report.camera.isUsable
            micEnabled = report.microphone.isUsable
            systemAudioEnabled = report.systemAudio.isUsable
        }

        // 2 s celebration when a permission goes from denied to granted.
        if let old {
            for source in RecordingSource.allCases {
                if !old.status(for: source).isUsable, report.status(for: source).isUsable {
                    celebrating.insert(source)
                    permissionController.close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                        self?.celebrating.remove(source)
                    }
                }
            }
        }

        availableCameras = CaptureDevices.cameras()
        availableMicrophones = CaptureDevices.microphones()
        // A device that got unplugged falls back to the system default.
        if let id = cameraDeviceID, !availableCameras.contains(where: { $0.id == id }) {
            cameraDeviceID = nil
        }
        if let id = microphoneDeviceID, !availableMicrophones.contains(where: { $0.id == id }) {
            microphoneDeviceID = nil
        }

        if report.screen.isUsable, let content = try? await RecordingEngine.availableContent() {
            availableDisplays = content.displays
            availableWindows = content.windows
            if let selected = selectedWindow, !content.windows.contains(where: { $0.id == selected.id }) {
                selectedWindow = nil
            }
            if let id = selectedDisplayID, !content.displays.contains(where: { $0.id == id }) {
                selectedDisplayID = nil
            }
        }
    }

    func status(for source: RecordingSource) -> SourceRowStatus {
        if celebrating.contains(source) { return .celebracion }
        guard let report = preflight else { return .normal }
        switch report.status(for: source) {
        case .available: return .normal
        case .permissionDenied: return .sinPermiso
        case .unavailable: return .noDisponible
        }
    }

    // MARK: - Names for subtitles

    var captureLabel: String {
        switch captureMode {
        case .screen:
            if let id = selectedDisplayID, let d = availableDisplays.first(where: { $0.id == id }), !d.isMain {
                return d.name
            }
            return L("app.capture.fullScreen")
        case .window:
            if let w = selectedWindow { return LF("app.capture.window", w.appName) }
            return L("app.capture.chooseWindow")
        case .region:
            if let r = regionRect { return LF("app.capture.region", Int(r.width), Int(r.height)) }
            return L("app.capture.drawRegion")
        }
    }

    var cameraSubtitle: String {
        guard cameraEnabled else { return L("app.camera.off") }
        return LF("app.camera.subtitle", cameraLayout.shape.displayName)
    }

    var micDeviceName: String {
        CaptureDevices.name(forMicrophone: microphoneDeviceID)
            ?? AVCaptureDevice.default(for: .audio)?.localizedName
            ?? RecordingSource.microphone.displayName
    }

    /// "Circle · FaceTime HD Camera" — shape plus which camera is feeding it.
    var cameraRowSubtitle: String {
        guard cameraEnabled else { return L("app.camera.off") }
        let shape = LF("app.camera.subtitle", cameraLayout.shape.displayName)
        guard let name = cameraDeviceName else { return shape }
        return "\(shape) · \(name)"
    }

    var cameraDeviceName: String? {
        CaptureDevices.name(forCamera: cameraDeviceID)
            ?? AVCaptureDevice.default(for: .video)?.localizedName
    }

    // MARK: - Configuration

    private var currentTarget: CaptureTarget {
        switch captureMode {
        case .screen:
            return .display(selectedDisplayID)
        case .window:
            if let w = selectedWindow { return .window(w.id) }
            return .display(selectedDisplayID)
        case .region:
            if let r = regionRect { return .region(displayID: selectedDisplayID, rect: r) }
            return .display(selectedDisplayID)
        }
    }

    // MARK: - Preview

    func openPreview() {
        showMainWindow(tab: .record)
    }

    /// Any change to what is captured goes through the one lifecycle rule.
    private func sourcesChanged() {
        updateCapture()
    }

    // MARK: - Capture lifecycle

    /// Everything that captures — screen, camera, microphone — runs only
    /// while a surface that shows it is on screen. Leaving the Record tab,
    /// closing or covering the window releases the devices: no camera light
    /// and no screen-sharing indicator when nobody is looking.
    func updateCapture() {
        let demand = CaptureDemand(
            previewVisible: mainWindow.showsPreview,
            panelOpen: panelIsOpen,
            recordingActive: isActive,
            sources: sourceSelection,
            permissions: preflight ?? .allAvailable)
        let plan = previewPlan()
        let monitoring = micMonitoringWanted
        let device = microphoneDeviceID
        // The decision is the use case's; the model only remembers what it
        // asked for so it does not re-open a session that is already open.
        micMonitoringWanted = SyncCaptureUseCase.intent(for: demand).wantsMicrophoneMonitor
        Task {
            await environment.syncCapture(demand: demand, plan: plan,
                                          monitoringMicrophone: monitoring, deviceID: device)
        }
    }

    /// What the preview should be showing right now, or nil when there is
    /// nothing with picture to show.
    private func previewPlan() -> RecordingPlan? {
        guard sourceSelection.hasVideo else { return nil }
        return .preview(sources: sourceSelection,
                        target: currentTarget,
                        devices: deviceSelection,
                        cameraLayout: cameraLayout,
                        quality: quality)
    }

    /// Picking another microphone re-opens the monitoring session on it.
    private func restartMicMonitoringIfNeeded() {
        guard micMonitoringWanted else { return }
        let device = microphoneDeviceID
        Task {
            await environment.microphone.stop()
            await environment.microphone.start(deviceID: device)
        }
    }

    func panelAppeared() {
        panelIsOpen = true
        Task {
            await refreshAll()
            updateCapture()
        }
    }

    func panelDisappeared() {
        panelIsOpen = false
        updateCapture()
    }

    // MARK: - Record

    func toggleRecording() {
        if isActive {
            Task { await stop() }
        } else if countdown == nil {
            requestStart()
        }
    }

    /// Mute/unmute the microphone live (the track stays continuous: real
    /// silence is written).
    func toggleMicMuted() {
        guard isActive, micEnabled else { return }
        micMuted.toggle()
        engine.setMicrophoneMuted(micMuted)
    }

    /// Turn the camera off/on live (PiP only; the light actually goes off).
    func toggleCameraHidden() {
        guard isActive, cameraEnabled, screenEnabled else { return }
        cameraHidden.toggle()
        let hidden = cameraHidden
        Task { await engine.setCameraHidden(hidden) }
        if hidden {
            cameraWindowController.close()
        } else {
            cameraWindowController.show(model: self)
        }
    }

    func togglePause() {
        environment.togglePause()
    }

    func requestStart() {
        errorMessage = nil
        guard anySourceEnabled else { return }
        Task {
            let report = await environment.permissions.report(requestingAccess: true)
            preflight = report
            switch environment.evaluateRecordability(sources: sourceSelection, permissions: report) {
            case .ready:
                startCountdown()
            case .noSources:
                errorMessage = RecordingError.noActiveSources.errorDescription
            case .blocked(let sources):
                unavailableSources = sources
                showUnavailableDialog = true
            }
        }
    }

    /// The user agreed to record without the unavailable sources.
    func startWithoutUnavailable() {
        for source in unavailableSources {
            switch source {
            case .screen: screenEnabled = false
            case .camera: cameraEnabled = false
            case .microphone: micEnabled = false
            case .systemAudio: systemAudioEnabled = false
            }
        }
        guard anySourceEnabled else {
            errorMessage = RecordingError.noActiveSources.errorDescription
            return
        }
        startCountdown()
    }

    /// 3·2·1 countdown with the mascot concentrating (Phase 4: 700 ms).
    private func startCountdown() {
        guard countdown == nil else { return }
        countdown = 3
        countdownController.show(model: self)
        tickCountdown()
    }

    private func tickCountdown() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self, let current = self.countdown else { return }
            if current <= 1 {
                self.countdown = nil
                self.countdownController.close()
                Task { await self.startRecording() }
            } else {
                self.countdown = current - 1
                self.tickCountdown()
            }
        }
    }

    private func startRecording() async {
        micMuted = false
        cameraHidden = false
        do {
            let blocked = try await environment.startRecording(.init(
                sources: sourceSelection,
                target: currentTarget,
                devices: deviceSelection,
                cameraLayout: cameraLayout,
                quality: quality,
                destinationFolder: destinationFolder))
            if !blocked.isEmpty {
                unavailableSources = blocked
                showUnavailableDialog = true
            }
        } catch {
            errorMessage = (error as? RecordingError)?.errorDescription ?? error.localizedDescription
        }
    }

    func stop() async {
        guard isActive else { return }
        do {
            // The use case stops, releases the capture and notifies: the
            // camera light must go out the moment the user says stop.
            let url = try await environment.stopRecording(elapsed: elapsed)
            lastRecordingURL = url
            library.newestURL = url
            refreshLibrary()

            // The pipeline that fed the writer stays alive to keep feeding the
            // preview — but it was built for RECORDING: full quality, 30 fps,
            // microphone and system audio. Leaving it running keeps the camera
            // light on and macOS showing "Currently Sharing" after the user
            // pressed stop, which is exactly what Grabi promises never to do.
            // Release it, and land on the recording that was just made.
            await engine.stopPreview()
            if mainWindow.isVisible { mainWindow.tab = .library }
            updateCapture()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Internal

    private func engineStateChanged(_ state: RecordingState) {
        engineState = state
        switch state {
        case .recording:
            if segmentStart == nil {
                if accumulated == 0 { elapsed = 0 } // fresh start
                segmentStart = Date()
                startTimer()
            }
            pillController.show(model: self)
            if cameraEnabled { cameraWindowController.show(model: self) }
            if screenEnabled, let area = captureAreaFrame() { borderController.show(frame: area) }
        case .paused:
            // Accumulate the recorded segment; the stopwatch freezes.
            if let start = segmentStart {
                accumulated += Date().timeIntervalSince(start)
                segmentStart = nil
            }
            timer = nil
        case .stopped, .failed, .idle:
            if let start = segmentStart {
                accumulated += Date().timeIntervalSince(start)
                segmentStart = nil
            }
            timer = nil
            elapsed = accumulated
            accumulated = 0
            pillController.close()
            cameraWindowController.close()
            borderController.close()
            if case .failed(let message) = state {
                errorMessage = message
            }
        default:
            break
        }
    }

    private func startTimer() {
        timer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                if let start = self.segmentStart {
                    self.elapsed = self.accumulated + Date().timeIntervalSince(start)
                }
            }
    }

    var elapsedText: String {
        let total = Int(elapsed)
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: - Miscellaneous actions

    func openRecordingsFolder() {
        NSWorkspace.shared.open(destinationFolder)
    }

    func showLastInFinder() {
        guard let url = lastRecordingURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openScreenSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    func openPermissionFlow(for source: RecordingSource) {
        permissionController.show(model: self, source: source)
    }

    func pickRegion() {
        regionController.show(model: self)
    }

    /// Visual picker of displays and windows (thumbnails).
    func pickCaptureSource() {
        capturePickerController.show(model: self)
    }

    func quit() {
        Task {
            if isActive { await stop() }
            NSApp.terminate(nil)
        }
    }

    /// Captured area in NS screen coordinates (bottom-left origin, global).
    /// Used by the recording border and the floating selfie frame.
    /// nil → no screen is captured (camera-only mode).
    func captureAreaFrame() -> NSRect? {
        guard screenEnabled else { return nil }

        func screen(for displayID: CGDirectDisplayID?) -> NSScreen? {
            let id = displayID ?? CGMainDisplayID()
            return NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id
            } ?? NSScreen.main
        }

        switch captureMode {
        case .screen:
            return screen(for: selectedDisplayID)?.frame
        case .region:
            guard let rect = regionRect, let scr = screen(for: selectedDisplayID) else {
                return screen(for: selectedDisplayID)?.frame
            }
            // regionRect: points relative to the screen, top-left origin.
            return NSRect(x: scr.frame.minX + rect.minX,
                          y: scr.frame.maxY - rect.minY - rect.height,
                          width: rect.width, height: rect.height)
        case .window:
            guard let window = selectedWindow, let primary = NSScreen.screens.first else {
                return screen(for: nil)?.frame
            }
            // SCWindow.frame: CG coordinates (top-left origin of the main
            // screen) → NS (bottom-left).
            let f = window.frame
            return NSRect(x: f.minX,
                          y: primary.frame.maxY - f.minY - f.height,
                          width: f.width, height: f.height)
        }
    }

}
