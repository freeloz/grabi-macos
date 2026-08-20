import Foundation
import AppKit
import Combine
import AVFoundation
import RecordEngine
import RecordUI

/// Modo de captura elegido en el segmented del panel.
enum CaptureMode: String, CaseIterable {
    case pantalla, ventana, region
}

/// Calidad de grabación (Ajustes, v0.1.1). "Estándar" es el comportamiento
/// de v0.1; "Nítida" captura a la resolución nativa de la fuente (hasta 4K)
/// y el motor escala el bitrate por área para mantener la calidad por píxel.
enum RecordingQuality: String, CaseIterable, Identifiable {
    case estandar, nitida

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .estandar: return "Estándar"
        case .nitida: return "Nítida"
        }
    }

    /// Pista honesta del costo (medido: ~2,9 GB/h en 1080p con contenido en
    /// movimiento; en nítida depende de la fuente — cifra por validar).
    var hint: String {
        switch self {
        case .estandar: return "Hasta 1080p · ~3 GB por hora"
        case .nitida: return "Resolución nativa, hasta 4K · ~6 GB por hora"
        }
    }

    /// Tope de ancho en píxeles; el aspecto siempre se conserva.
    var targetWidth: Int {
        switch self {
        case .estandar: return 1920
        case .nitida: return 3840
        }
    }
}

/// Estado de la UI de Grabi: fuentes, captura, cámara, grabación y ventanas.
@MainActor
final class GrabiAppModel: ObservableObject {
    let engine = RecordingEngine()

    // MARK: Fuentes
    @Published var screenEnabled = true { didSet { sourcesChanged() } }
    @Published var cameraEnabled = true { didSet { sourcesChanged() } }
    @Published var micEnabled = true { didSet { sourcesChanged() } }
    @Published var systemAudioEnabled = true { didSet { sourcesChanged() } }

    @Published private(set) var preflight: PreflightReport?
    @Published private(set) var celebrating: Set<RecordingSource> = []

    // MARK: Captura
    @Published var captureMode: CaptureMode = .pantalla { didSet { sourcesChanged() } }
    @Published private(set) var availableDisplays: [DisplayInfo] = []
    @Published private(set) var availableWindows: [WindowInfo] = []
    @Published var selectedDisplayID: CGDirectDisplayID? { didSet { sourcesChanged() } }
    @Published var selectedWindow: WindowInfo? { didSet { sourcesChanged() } }
    @Published var regionRect: CGRect? { didSet { sourcesChanged() } }

    // MARK: Cámara (persistida entre sesiones)
    @Published var cameraLayout: CameraLayout = GrabiAppModel.loadCameraLayout() {
        didSet {
            engine.updateCameraLayout(cameraLayout)
            Self.saveCameraLayout(cameraLayout)
        }
    }

    // MARK: Estado de grabación
    @Published private(set) var engineState: RecordingState = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var countdown: Int?
    @Published var errorMessage: String?
    @Published private(set) var lastRecordingURL: URL?
    @Published private(set) var micLevel: Double = 0
    @Published private(set) var systemLevel: Double = 0
    @Published var showUnavailableDialog = false
    @Published private(set) var unavailableSources: [RecordingSource] = []

    // MARK: Preferencias
    @Published var destinationFolder: URL {
        didSet { UserDefaults.standard.set(destinationFolder.path, forKey: "destinationFolder") }
    }
    @Published var onboardingDone: Bool {
        didSet { UserDefaults.standard.set(onboardingDone, forKey: "onboardingDone") }
    }
    @Published var quality: RecordingQuality {
        didSet {
            UserDefaults.standard.set(quality.rawValue, forKey: "recordingQuality")
            sourcesChanged() // la vista previa se reinicia a la nueva resolución
        }
    }

    // Ventanas gestionadas
    let previewController = PreviewWindowController()
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
            .appendingPathComponent("Movies/Grabaciones", isDirectory: true)
        if let stored = UserDefaults.standard.string(forKey: "destinationFolder") {
            destinationFolder = URL(fileURLWithPath: stored, isDirectory: true)
        } else {
            destinationFolder = defaultFolder
        }
        onboardingDone = UserDefaults.standard.bool(forKey: "onboardingDone")
        quality = RecordingQuality(rawValue: UserDefaults.standard.string(forKey: "recordingQuality") ?? "") ?? .estandar

        engine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.engineStateChanged(state) }
            .store(in: &cancellables)

        engine.onMicLevel = { [weak self] level in
            DispatchQueue.main.async { self?.micLevel = level }
        }
        engine.onSystemAudioLevel = { [weak self] level in
            DispatchQueue.main.async { self?.systemLevel = level }
        }

        // Atajos globales: ⌘⇧2 grabar/detener · ⌘⇧P pausar/reanudar.
        hotkeys.onToggleRecord = { [weak self] in
            Task { @MainActor in self?.toggleRecording() }
        }
        hotkeys.onTogglePause = { [weak self] in
            Task { @MainActor in self?.togglePause() }
        }
        hotkeys.register()

        NotificationManager.shared.configure(model: self)

        // Al volver de Ajustes del Sistema, re-chequear permisos y celebrar
        // los recién concedidos (Fase 3 §04).
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshAll() }
        }

        Task { await refreshAll(applyDefaults: true) }
    }

    // MARK: - Preflight y contenido

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

        // Celebración 2 s cuando un permiso pasa de denegado a concedido.
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

    // MARK: - Nombres para subtítulos

    var captureLabel: String {
        switch captureMode {
        case .pantalla:
            if let id = selectedDisplayID, let d = availableDisplays.first(where: { $0.id == id }), !d.isMain {
                return d.name
            }
            return "Pantalla completa · integrada"
        case .ventana:
            if let w = selectedWindow { return "Ventana: \(w.appName)" }
            return "Elige una ventana…"
        case .region:
            if let r = regionRect { return "Región \(Int(r.width))×\(Int(r.height))" }
            return "Dibuja una región…"
        }
    }

    var cameraSubtitle: String {
        guard cameraEnabled else { return "Apagada" }
        return "\(cameraLayout.shape.displayName) · muévela en la vista previa"
    }

    var micDeviceName: String {
        AVCaptureDevice.default(for: .audio)?.localizedName ?? "Micrófono"
    }

    // MARK: - Configuración

    private var currentTarget: CaptureTarget {
        switch captureMode {
        case .pantalla:
            return .display(selectedDisplayID)
        case .ventana:
            if let w = selectedWindow { return .window(w.id) }
            return .display(selectedDisplayID)
        case .region:
            if let r = regionRect { return .region(displayID: selectedDisplayID, rect: r) }
            return .display(selectedDisplayID)
        }
    }

    private func buildConfiguration() throws -> RecordingConfiguration {
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let url = destinationFolder.appendingPathComponent("grabacion-\(formatter.string(from: Date())).mov")
        return RecordingConfiguration(
            capturesScreen: screenEnabled,
            capturesCamera: cameraEnabled,
            capturesMicrophone: micEnabled,
            capturesSystemAudio: systemAudioEnabled,
            outputURL: url,
            targetWidth: quality.targetWidth,
            target: currentTarget,
            cameraLayout: cameraLayout)
    }

    // MARK: - Vista previa

    func openPreview() {
        previewController.show(model: self)
        restartPreviewIfNeeded()
    }

    func restartPreviewIfNeeded() {
        guard previewController.isVisible else { return }
        guard screenEnabled || cameraEnabled else {
            Task { await engine.stopPreview() }
            return
        }
        Task {
            if let config = try? buildConfiguration() {
                try? await engine.startPreview(configuration: config)
            }
        }
    }

    func previewClosed() {
        Task { await engine.stopPreview() }
    }

    private func sourcesChanged() {
        restartPreviewIfNeeded()
    }

    // MARK: - Monitoreo de mic (panel abierto)

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

    // MARK: - Grabar

    func toggleRecording() {
        if isActive {
            Task { await stop() }
        } else if countdown == nil {
            requestStart()
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

    /// El usuario aceptó grabar sin las fuentes no disponibles.
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
            errorMessage = RecordingError.sinFuentesActivas.errorDescription
            return
        }
        startCountdown()
    }

    /// Cuenta regresiva 3·2·1 con la mascota concentrándose (Fase 4: 700 ms).
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
            NotificationManager.shared.showRecordingDone(url: url, duration: elapsed, model: self)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Interno

    private func engineStateChanged(_ state: RecordingState) {
        engineState = state
        switch state {
        case .recording:
            if segmentStart == nil {
                if accumulated == 0 { elapsed = 0 } // arranque nuevo
                segmentStart = Date()
                startTimer()
            }
            pillController.show(model: self)
            if cameraEnabled { cameraWindowController.show(model: self) }
            if screenEnabled, let area = captureAreaFrame() { borderController.show(frame: area) }
        case .paused:
            // Acumular el tramo grabado; el cronómetro se congela.
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

    // MARK: - Acciones varias

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

    /// Selector visual de pantallas y ventanas (miniaturas).
    func pickCaptureSource() {
        capturePickerController.show(model: self)
    }

    func quit() {
        Task {
            if isActive { await stop() }
            NSApp.terminate(nil)
        }
    }

    /// Área capturada en coordenadas de pantalla NS (origen abajo-izquierda,
    /// globales). La usan el borde de grabación y el recuadro selfie flotante.
    /// nil → no se captura pantalla (modo cámara-sola).
    func captureAreaFrame() -> NSRect? {
        guard screenEnabled else { return nil }

        func screen(for displayID: CGDirectDisplayID?) -> NSScreen? {
            let id = displayID ?? CGMainDisplayID()
            return NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id
            } ?? NSScreen.main
        }

        switch captureMode {
        case .pantalla:
            return screen(for: selectedDisplayID)?.frame
        case .region:
            guard let rect = regionRect, let scr = screen(for: selectedDisplayID) else {
                return screen(for: selectedDisplayID)?.frame
            }
            // regionRect: puntos relativos a la pantalla, origen arriba-izquierda.
            return NSRect(x: scr.frame.minX + rect.minX,
                          y: scr.frame.maxY - rect.minY - rect.height,
                          width: rect.width, height: rect.height)
        case .ventana:
            guard let window = selectedWindow, let primary = NSScreen.screens.first else {
                return screen(for: nil)?.frame
            }
            // SCWindow.frame: coordenadas CG (origen arriba-izquierda de la
            // pantalla principal) → NS (abajo-izquierda).
            let f = window.frame
            return NSRect(x: f.minX,
                          y: primary.frame.maxY - f.minY - f.height,
                          width: f.width, height: f.height)
        }
    }

    // MARK: - Persistencia del layout de cámara

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
