import Foundation
import AVFoundation
import CoreVideo
import Combine

/// Estados observables del motor.
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

/// Fachada pública del motor de grabación.
///
/// Flujo: `Preflight.check()` → (opcional) `startPreview(configuration:)`
/// para ver el lienzo compuesto en vivo → `start(configuration:)` →
/// `pause()`/`resume()` → `stop()`. La vista previa y la grabación comparten
/// el mismo pipeline de captura: iniciar la grabación con la misma
/// configuración no reinicia cámaras ni streams.
public final class RecordingEngine: ObservableObject {
    @Published public private(set) var state: RecordingState = .idle
    /// true mientras el pipeline emite frames de vista previa.
    @Published public private(set) var isPreviewing = false

    /// Frames compuestos (pantalla+cámara tal como se graban), BGRA.
    /// Se invoca en una cola de captura: la UI debe saltar a main si toca vistas.
    public var onPreviewFrame: ((CVPixelBuffer) -> Void)? {
        didSet { pipeline?.onPreviewFrame = onPreviewFrame }
    }

    private var pipeline: CapturePipeline?
    private var micCapturer: MicrophoneCapturer?
    private var writer: MovieWriter?

    public init() {}

    // MARK: - Descubrimiento

    /// Chequeo previo: qué fuentes están disponibles y con permiso.
    public static func preflight(requestingAccess: Bool = true) async -> PreflightReport {
        await Preflight.check(requestingAccess: requestingAccess)
    }

    /// Pantallas y ventanas disponibles para capturar.
    public static func availableContent() async throws -> ShareableContent {
        try await ShareableContent.current()
    }

    // MARK: - Vista previa

    /// Arranca el pipeline de captura sin escribir a disco. La UI recibe los
    /// frames por `onPreviewFrame`. Si ya hay una vista previa con otra
    /// configuración, se reinicia con la nueva.
    public func startPreview(configuration config: RecordingConfiguration) async throws {
        guard !state.isActive else {
            throw RecordingError.estadoInvalido("no se puede cambiar la vista previa durante una grabación")
        }
        if let pipeline, pipeline.isCompatible(with: config) {
            pipeline.updateCameraLayout(config.cameraLayout)
            setPreviewing(true)
            return
        }
        await teardownPipeline()
        guard config.hasVideo else { return } // sin video no hay nada que previsualizar
        let pipeline = CapturePipeline(config: config)
        pipeline.onPreviewFrame = onPreviewFrame
        pipeline.onFatalError = { [weak self] error in
            Task { await self?.handleFatalError(error) }
        }
        do {
            try await pipeline.start()
        } catch {
            await pipeline.stop()
            throw (error as? RecordingError) ?? .capturaInterrumpida(error.localizedDescription)
        }
        self.pipeline = pipeline
        setPreviewing(true)
    }

    /// Detiene la vista previa (si no se está grabando, apaga la captura).
    public func stopPreview() async {
        setPreviewing(false)
        guard !state.isActive else { return } // el pipeline sigue: está grabando
        await teardownPipeline()
    }

    /// Cambia forma/posición/tamaño de la cámara EN VIVO (vista previa y grabación).
    public func updateCameraLayout(_ layout: CameraLayout) {
        pipeline?.updateCameraLayout(layout)
    }

    // MARK: - Grabación

    public func start(configuration config: RecordingConfiguration) async throws {
        guard !state.isActive else {
            throw RecordingError.estadoInvalido("ya hay una grabación en curso")
        }
        guard config.hasAnySource else {
            throw RecordingError.sinFuentesActivas
        }
        setState(.starting)

        do {
            try await startRecordingPipeline(config: config)
            setState(.recording)
        } catch {
            // Limpieza total: nada debe quedar corriendo ni archivos a medias
            // (salvo la vista previa, que se conserva si estaba activa).
            await stopMic()
            writer?.cancel()
            writer = nil
            if !isPreviewing { await teardownPipeline() }
            let recError = (error as? RecordingError) ?? .capturaInterrumpida(error.localizedDescription)
            setState(.failed(recError))
            throw recError
        }
    }

    private func startRecordingPipeline(config: RecordingConfiguration) async throws {
        // Re-validar permisos justo antes de empezar: nunca fallar a mitad de
        // grabación por algo detectable ahora.
        let report = await Preflight.check(requestingAccess: true)
        if config.capturesScreen || config.capturesSystemAudio {
            guard report.screen.isUsable else { throw RecordingError.permisoPantallaDenegado }
        }
        if config.capturesCamera {
            switch report.camera {
            case .available: break
            case .permissionDenied: throw RecordingError.permisoCamaraDenegado
            case .unavailable: throw RecordingError.camaraNoDisponible
            }
        }
        if config.capturesMicrophone {
            switch report.microphone {
            case .available: break
            case .permissionDenied: throw RecordingError.permisoMicrofonoDenegado
            case .unavailable: throw RecordingError.microfonoNoDisponible
            }
        }

        // Pipeline: reusar el de la vista previa si es compatible (la captura
        // ya está corriendo); si no, construir uno nuevo.
        let pipeline: CapturePipeline
        if let existing = self.pipeline, existing.isCompatible(with: config) {
            pipeline = existing
            pipeline.updateCameraLayout(config.cameraLayout)
        } else {
            await teardownPipeline()
            pipeline = CapturePipeline(config: config)
            pipeline.onPreviewFrame = onPreviewFrame
            pipeline.onFatalError = { [weak self] error in
                Task { await self?.handleFatalError(error) }
            }
            try await pipeline.start()
            self.pipeline = pipeline
        }

        // Micrófono: se configura primero (sin arrancar) para conocer sus
        // canales nativos; solo captura durante la grabación.
        var mic: MicrophoneCapturer?
        if config.capturesMicrophone {
            let m = MicrophoneCapturer()
            try m.configure(deviceID: config.microphoneDeviceID)
            mic = m
        }

        // Writer con SOLO las pistas de las fuentes activadas.
        var videoSpec: MovieWriter.VideoSpec?
        if let size = pipeline.canvasSize, config.hasVideo {
            videoSpec = .init(width: size.width, height: size.height,
                              bitrate: config.videoBitrate, fps: config.framesPerSecond)
        }
        let writer = try MovieWriter(
            outputURL: config.outputURL,
            video: videoSpec,
            includeMicrophone: config.capturesMicrophone,
            microphoneChannels: mic?.nativeChannelCount ?? 2,
            includeSystemAudio: config.capturesSystemAudio)

        if let mic {
            mic.onAudio = { sample in
                writer.appendMicrophone(sample)
            }
            micCapturer = mic
            await mic.start()
        }

        self.writer = writer
        pipeline.attachWriter(writer)
    }

    // MARK: - Pausa

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

    /// Detiene la grabación y devuelve la URL del archivo finalizado.
    /// La vista previa (si estaba activa) sigue corriendo.
    @discardableResult
    public func stop() async throws -> URL {
        switch state {
        case .recording, .paused: break
        default: throw RecordingError.estadoInvalido("no hay ninguna grabación en curso")
        }
        setState(.stopping)

        // Orden: primero dejan de llegar buffers al writer, después se
        // finaliza — así el archivo queda siempre reproducible.
        pipeline?.detachWriter()
        await stopMic()
        if !isPreviewing {
            await teardownPipeline()
        }

        guard let writer else {
            setState(.failed(.estadoInvalido("no había writer activo")))
            throw RecordingError.estadoInvalido("no había writer activo")
        }
        self.writer = nil
        do {
            let url = try await writer.finish()
            setState(.stopped(url))
            return url
        } catch {
            let recError = (error as? RecordingError) ?? .escrituraFallida(error.localizedDescription)
            setState(.failed(recError))
            throw recError
        }
    }

    // MARK: - Interno

    private func handleFatalError(_ error: Error) async {
        switch state {
        case .recording, .paused:
            setState(.stopping)
            await stopMic()
            await teardownPipeline()
            setPreviewing(false)
            // Intentar salvar lo grabado hasta ahora: el archivo queda finalizado.
            if let writer {
                self.writer = nil
                _ = try? await writer.finish()
            }
            setState(.failed(.capturaInterrumpida(error.localizedDescription)))
        default:
            // Falló la vista previa (sin grabación): apagar en silencio.
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
