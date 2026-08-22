import Foundation
import AppKit
import Combine
import AVFoundation
import RecordEngine
import RecordUI

/// Capture mode chosen in the panel's segmented control.
enum CaptureMode: String, CaseIterable {
    case screen, window, region
}

/// Recording quality (Settings, v0.1.1). "Standard" is the v0.1 behavior;
/// "Sharp" captures at the source's native resolution (up to 4K) and the
/// engine scales the bitrate by area to keep the per-pixel quality.
enum RecordingQuality: String, CaseIterable, Identifiable {
    case standard, sharp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return L("app.quality.standard")
        case .sharp: return L("app.quality.sharp")
        }
    }

    /// Honest hint about the cost (measured: ~2.9 GB/h at 1080p with moving
    /// content; in sharp it depends on the source — figure pending validation).
    var hint: String {
        switch self {
        case .standard: return L("app.quality.standard.hint")
        case .sharp: return L("app.quality.sharp.hint")
        }
    }

    /// Width cap in pixels; the aspect ratio is always preserved.
    var targetWidth: Int {
        switch self {
        case .standard: return 1920
        case .sharp: return 3840
        }
    }
}

/// Grabi UI state: sources, capture, camera, recording, and windows.
@MainActor
final class GrabiAppModel: ObservableObject {
    let engine = RecordingEngine()

    // MARK: Sources
    @Published var screenEnabled = true { didSet { sourcesChanged() } }
    @Published var cameraEnabled = true { didSet { sourcesChanged() } }
    @Published var micEnabled = true { didSet { sourcesChanged() } }
    @Published var systemAudioEnabled = true { didSet { sourcesChanged() } }

    @Published private(set) var preflight: PreflightReport?
    @Published private(set) var celebrating: Set<RecordingSource> = []

    // MARK: Capture
    @Published var captureMode: CaptureMode = .screen { didSet { sourcesChanged() } }
    @Published private(set) var availableDisplays: [DisplayInfo] = []
    @Published private(set) var availableWindows: [WindowInfo] = []
    @Published var selectedDisplayID: CGDirectDisplayID? { didSet { sourcesChanged() } }
    @Published var selectedWindow: WindowInfo? { didSet { sourcesChanged() } }
    @Published var regionRect: CGRect? { didSet { sourcesChanged() } }

    // MARK: Camera (persisted across sessions)
    @Published var cameraLayout: CameraLayout = GrabiAppModel.loadCameraLayout() {
        didSet {
            engine.updateCameraLayout(cameraLayout)
            Self.saveCameraLayout(cameraLayout)
        }
    }

    // MARK: Recording state
    @Published private(set) var engineState: RecordingState = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var countdown: Int?
    @Published var errorMessage: String?
    @Published private(set) var lastRecordingURL: URL?
    @Published private(set) var micLevel: Double = 0
    @Published private(set) var systemLevel: Double = 0
    @Published var showUnavailableDialog = false
    @Published private(set) var unavailableSources: [RecordingSource] = []
    /// Live controls during recording (floating pill).
    @Published private(set) var micMuted = false
    @Published private(set) var cameraHidden = false

    // MARK: Preferences
    @Published var destinationFolder: URL {
        didSet {
            UserDefaults.standard.set(destinationFolder.path, forKey: "destinationFolder")
            refreshLibrary()
        }
    }
    /// Menu bar item: quick access without opening the window (Phase 6).
    @Published var quickAccessEnabled: Bool {
        didSet { UserDefaults.standard.set(quickAccessEnabled, forKey: "quickAccessEnabled") }
    }
    @Published var onboardingDone: Bool {
        didSet { UserDefaults.standard.set(onboardingDone, forKey: "onboardingDone") }
    }
    @Published var quality: RecordingQuality {
        didSet {
            UserDefaults.standard.set(quality.rawValue, forKey: "recordingQuality")
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

    var isRecording: Bool { engineState == .recording }
    var isPaused: Bool { engineState == .paused }
    var isActive: Bool { engineState.isActive }

    var anySourceEnabled: Bool {
        screenEnabled || cameraEnabled || micEnabled || systemAudioEnabled
    }

    init() {
        let defaultFolder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies/Grabi", isDirectory: true)
        if let stored = UserDefaults.standard.string(forKey: "destinationFolder") {
            destinationFolder = URL(fileURLWithPath: stored, isDirectory: true)
        } else {
            destinationFolder = defaultFolder
        }
        onboardingDone = UserDefaults.standard.bool(forKey: "onboardingDone")
        quickAccessEnabled = UserDefaults.standard.object(forKey: "quickAccessEnabled") as? Bool ?? true
        quality = RecordingQuality(rawValue: UserDefaults.standard.string(forKey: "recordingQuality") ?? "") ?? .standard

        engine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.engineStateChanged(state) }
            .store(in: &cancellables)

        // One preview stream, delivered to whichever surface is on screen.
        engine.onPreviewFrame = { [weak self] pixelBuffer in
            DispatchQueue.main.async { self?.mainWindow.receive(pixelBuffer) }
        }

        engine.onMicLevel = { [weak self] level in
            DispatchQueue.main.async { self?.micLevel = level }
        }
        engine.onSystemAudioLevel = { [weak self] level in
            DispatchQueue.main.async { self?.systemLevel = level }
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
        restartPreviewIfNeeded()
    }

    /// Stops the preview without touching an ongoing recording.
    func pausePreview() {
        guard !isActive else { return }
        Task { await engine.stopPreview() }
    }

    func mainWindowClosed() {
        // Closing the window must never stop a recording: only the preview.
        if !isActive { Task { await engine.stopPreview() } }
    }

    /// The in-window welcome is done (permissions granted or postponed).
    func finishWelcome(startRecording: Bool) {
        onboardingDone = true
        Task {
            await refreshAll(applyDefaults: true)
            restartPreviewIfNeeded()
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
        AVCaptureDevice.default(for: .audio)?.localizedName ?? RecordingSource.microphone.displayName
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

    /// The preview is for framing, not for pixel-peeping: capping it at
    /// 1440 px and 15 fps keeps a 4K "Sharp" setup from pinning the CPU
    /// while the window merely sits open. Recording rebuilds the pipeline
    /// at full quality during the 3·2·1 countdown.
    private static let previewWidth = 1280
    private static let previewFPS = 10

    private func buildConfiguration(forPreview: Bool = false) throws -> RecordingConfiguration {
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        // Neutral branded name, identical in every language (v0.1.2
        // decision): fixed format, POSIX calendar/locale so it doesn't
        // change with the regional settings.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = destinationFolder.appendingPathComponent("Grabi \(formatter.string(from: Date())).mov")
        return RecordingConfiguration(
            capturesScreen: screenEnabled,
            capturesCamera: cameraEnabled,
            // The microphone only ever runs while recording.
            capturesMicrophone: micEnabled && !forPreview,
            capturesSystemAudio: systemAudioEnabled && !forPreview,
            outputURL: url,
            targetWidth: forPreview ? min(quality.targetWidth, Self.previewWidth) : quality.targetWidth,
            framesPerSecond: forPreview ? Self.previewFPS : 30,
            target: currentTarget,
            cameraLayout: cameraLayout)
    }

    // MARK: - Preview

    func openPreview() {
        showMainWindow(tab: .record)
    }

    func restartPreviewIfNeeded() {
        guard mainWindow.showsPreview else { return }
        guard screenEnabled || cameraEnabled else {
            Task { await engine.stopPreview() }
            return
        }
        Task {
            if let config = try? buildConfiguration(forPreview: true) {
                try? await engine.startPreview(configuration: config)
            }
        }
    }

    private func sourcesChanged() {
        restartPreviewIfNeeded()
    }

    // MARK: - Mic monitoring (panel open)

    func panelAppeared() {
        Task {
            await refreshAll()
            if micEnabled, preflight?.microphone.isUsable == true {
                micMonitoringWanted = true
                await engine.startMicrophoneMonitoring()
            }
        }
    }

    func panelDisappeared() {
        guard micMonitoringWanted else { return }
        micMonitoringWanted = false
        Task { await engine.stopMicrophoneMonitoring() }
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
        if isPaused {
            engine.resume()
        } else if isRecording {
            engine.pause()
        }
    }

    func requestStart() {
        errorMessage = nil
        guard anySourceEnabled else { return }
        Task {
            let report = await RecordingEngine.preflight(requestingAccess: true)
            preflight = report
            var enabled: [RecordingSource] = []
            if screenEnabled { enabled.append(.screen) }
            if cameraEnabled { enabled.append(.camera) }
            if micEnabled { enabled.append(.microphone) }
            if systemAudioEnabled { enabled.append(.systemAudio) }
            let unusable = enabled.filter { !report.status(for: $0).isUsable }
            if unusable.isEmpty {
                startCountdown()
            } else {
                unavailableSources = unusable
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
            let config = try buildConfiguration()
            try await engine.start(configuration: config)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() async {
        guard isActive else { return }
        do {
            let url = try await engine.stop()
            lastRecordingURL = url
            library.newestURL = url
            refreshLibrary()
            NotificationManager.shared.showRecordingDone(url: url, duration: elapsed, model: self)
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
            if case .failed(let error) = state {
                errorMessage = error.errorDescription
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

    // MARK: - Camera layout persistence

    private static func loadCameraLayout() -> CameraLayout {
        let d = UserDefaults.standard
        guard d.object(forKey: "camLayout.h") != nil,
              let shape = CameraShape(rawValue: d.string(forKey: "camLayout.shape") ?? "")
        else { return .default }
        return CameraLayout(
            shape: shape,
            origin: CGPoint(x: d.double(forKey: "camLayout.x"), y: d.double(forKey: "camLayout.y")),
            height: d.double(forKey: "camLayout.h"))
    }

    private static func saveCameraLayout(_ layout: CameraLayout) {
        let d = UserDefaults.standard
        d.set(layout.shape.rawValue, forKey: "camLayout.shape")
        d.set(layout.origin.x, forKey: "camLayout.x")
        d.set(layout.origin.y, forKey: "camLayout.y")
        d.set(layout.height, forKey: "camLayout.h")
    }
}
