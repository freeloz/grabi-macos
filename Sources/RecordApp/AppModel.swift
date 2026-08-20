import Foundation
import AppKit
import Combine
import RecordEngine

/// Estado de la UI: toggles, preflight, cronómetro y puente con el motor.
@MainActor
final class AppModel: ObservableObject {
    let engine = RecordingEngine()

    // Toggles de las 4 fuentes.
    @Published var screenEnabled = true
    @Published var cameraEnabled = true
    @Published var micEnabled = true
    @Published var systemAudioEnabled = true

    @Published private(set) var engineState: RecordingState = .idle
    @Published private(set) var preflight: PreflightReport?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var errorMessage: String?
    @Published private(set) var lastRecordingURL: URL?

    // Diálogo "fuentes no disponibles": se muestra ANTES de iniciar y ofrece
    // grabar sin ellas.
    @Published var showUnavailableDialog = false
    @Published private(set) var unavailableSources: [RecordingSource] = []

    // Controles de prueba de FASE A (UI provisional): target y pausa.
    @Published var selectedTarget: CaptureTarget = .mainDisplay
    @Published private(set) var availableWindows: [WindowInfo] = []

    var isPaused: Bool {
        if case .paused = engineState { return true }
        return false
    }

    func refreshWindows() async {
        availableWindows = (try? await RecordingEngine.availableContent())?.windows ?? []
    }

    func togglePause() {
        if isPaused { engine.resume() } else { engine.pause() }
    }

    private var cancellables = Set<AnyCancellable>()
    private var timer: AnyCancellable?
    private var recordingStartedAt: Date?
    private var appliedDefaultToggles = false

    init() {
        engine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.engineStateChanged(state) }
            .store(in: &cancellables)
    }

    var isRecording: Bool {
        if case .recording = engineState { return true }
        return false
    }

    var isBusy: Bool { engineState.isActive }

    var anySourceEnabled: Bool {
        screenEnabled || cameraEnabled || micEnabled || systemAudioEnabled
    }

    func enabledSources() -> [RecordingSource] {
        var sources: [RecordingSource] = []
        if screenEnabled { sources.append(.screen) }
        if cameraEnabled { sources.append(.camera) }
        if micEnabled { sources.append(.microphone) }
        if systemAudioEnabled { sources.append(.systemAudio) }
        return sources
    }

    func isEnabled(_ source: RecordingSource) -> Bool {
        switch source {
        case .screen: return screenEnabled
        case .camera: return cameraEnabled
        case .microphone: return micEnabled
        case .systemAudio: return systemAudioEnabled
        }
    }

    func setEnabled(_ source: RecordingSource, _ value: Bool) {
        switch source {
        case .screen: screenEnabled = value
        case .camera: cameraEnabled = value
        case .microphone: micEnabled = value
        case .systemAudio: systemAudioEnabled = value
        }
    }

    // MARK: - Preflight

    /// Primer arranque: pide los permisos que falten y deja activados por
    /// defecto solo los toggles de fuentes realmente disponibles.
    func refreshPreflight(requestingAccess: Bool = true) async {
        let report = await RecordingEngine.preflight(requestingAccess: requestingAccess)
        preflight = report
        if !appliedDefaultToggles {
            appliedDefaultToggles = true
            for source in RecordingSource.allCases {
                setEnabled(source, report.status(for: source).isUsable)
            }
            // Si nada está disponible aún (permisos recién pedidos), dejamos
            // los toggles como estén; el usuario puede reintentar tras dar permisos.
        }
    }

    func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Start / Stop

    func toggleRecording() {
        Task {
            if isRecording {
                await stop()
            } else {
                await requestStart()
            }
        }
    }

    /// Chequeo previo antes de iniciar: si alguna fuente activada no es usable,
    /// avisa y ofrece grabar sin ella. Nunca se llega a fallar a mitad de grabación.
    private func requestStart() async {
        errorMessage = nil
        let report = await RecordingEngine.preflight(requestingAccess: true)
        preflight = report

        let unusable = enabledSources().filter { !report.status(for: $0).isUsable }
        if unusable.isEmpty {
            await start(excluding: [])
        } else {
            unavailableSources = unusable
            showUnavailableDialog = true
        }
    }

    /// El usuario aceptó grabar sin las fuentes no disponibles.
    func startWithoutUnavailable() {
        Task { await start(excluding: unavailableSources) }
    }

    private func start(excluding: [RecordingSource]) async {
        for source in excluding { setEnabled(source, false) }
        guard anySourceEnabled else {
            errorMessage = RecordingError.sinFuentesActivas.errorDescription
            return
        }

        do {
            let outputURL = try Self.makeOutputURL()
            let config = RecordingConfiguration(
                capturesScreen: screenEnabled,
                capturesCamera: cameraEnabled,
                capturesMicrophone: micEnabled,
                capturesSystemAudio: systemAudioEnabled,
                outputURL: outputURL,
                target: selectedTarget)
            try await engine.start(configuration: config)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stop() async {
        do {
            let url = try await engine.stop()
            lastRecordingURL = url
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func showLastRecordingInFinder() {
        guard let url = lastRecordingURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Interno

    private func engineStateChanged(_ state: RecordingState) {
        engineState = state
        switch state {
        case .recording:
            recordingStartedAt = Date()
            elapsed = 0
            timer = Timer.publish(every: 0.5, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    guard let self, let start = self.recordingStartedAt else { return }
                    self.elapsed = Date().timeIntervalSince(start)
                }
        case .stopped, .failed, .idle:
            timer = nil
            recordingStartedAt = nil
            if case .failed(let error) = state {
                errorMessage = error.errorDescription
            }
        default:
            break
        }
    }

    /// ~/Movies/Grabaciones/grabacion-AAAA-MM-DD-HHMMSS.mov (crea la carpeta si no existe).
    private static func makeOutputURL() throws -> URL {
        let dir = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Movies/Grabaciones", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let name = "grabacion-\(formatter.string(from: Date())).mov"
        return dir.appendingPathComponent(name)
    }

    static func formatElapsed(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
