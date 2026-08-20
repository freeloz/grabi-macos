import Foundation
import AVFoundation
import CoreVideo
import Combine

/// Estados observables del motor.
public enum RecordingState: Equatable {
    case idle
    case starting
    case recording
    case stopping
    case stopped(URL)
    case failed(RecordingError)

    public var isActive: Bool {
        switch self {
        case .starting, .recording, .stopping: return true
        default: return false
        }
    }
}

/// Caja thread-safe para "el último frame de cámara". La cola de la cámara
/// escribe y la cola de pantalla lee (para el compositing PiP); un NSLock
/// basta porque solo guardamos una referencia.
private final class LatestFrameBox {
    private let lock = NSLock()
    private var buffer: CVPixelBuffer?

    var value: CVPixelBuffer? {
        get { lock.lock(); defer { lock.unlock() }; return buffer }
        set { lock.lock(); defer { lock.unlock() }; buffer = newValue }
    }
}

/// Fachada pública del motor de grabación.
///
/// Uso: `Preflight.check()` para saber qué fuentes son usables (la UI avisa
/// al usuario ANTES de iniciar), luego `start(configuration:)` / `stop()`.
public final class RecordingEngine: ObservableObject {
    @Published public private(set) var state: RecordingState = .idle

    private var screenCapturer: ScreenCapturer?
    private var cameraCapturer: CameraCapturer?
    private var micCapturer: MicrophoneCapturer?
    private var writer: MovieWriter?

    public init() {}

    /// Chequeo previo: qué fuentes están disponibles y con permiso.
    public static func preflight(requestingAccess: Bool = true) async -> PreflightReport {
        await Preflight.check(requestingAccess: requestingAccess)
    }

    // MARK: - Start

    public func start(configuration config: RecordingConfiguration) async throws {
        guard !state.isActive else {
            throw RecordingError.estadoInvalido("ya hay una grabación en curso")
        }
        guard config.hasAnySource else {
            throw RecordingError.sinFuentesActivas
        }
        setState(.starting)

        do {
            try await startPipeline(config: config)
            setState(.recording)
        } catch {
            // Limpieza total: nada debe quedar corriendo ni archivos a medias.
            await teardownCapturers()
            writer?.cancel()
            writer = nil
            let recError = (error as? RecordingError) ?? .capturaInterrumpida(error.localizedDescription)
            setState(.failed(recError))
            throw recError
        }
    }

    private func startPipeline(config: RecordingConfiguration) async throws {
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

        // 1. Configurar la cámara primero (sin arrancarla) para conocer sus
        //    dimensiones: en modo cámara-sola definen el tamaño del video.
        var camera: CameraCapturer?
        if config.capturesCamera {
            let cam = CameraCapturer()
            try cam.configure(deviceID: config.cameraDeviceID)
            camera = cam
        }

        // 2. Tamaño del video de salida.
        var videoSpec: MovieWriter.VideoSpec?
        if config.capturesScreen {
            let size = ScreenCapturer.outputSize(displayID: config.displayID, targetWidth: config.targetWidth)
            videoSpec = .init(width: size.width, height: size.height,
                              bitrate: config.videoBitrate, fps: config.framesPerSecond)
        } else if let camera {
            videoSpec = .init(width: camera.dimensions.width, height: camera.dimensions.height,
                              bitrate: config.videoBitrate, fps: config.framesPerSecond)
        }
        // Sin video (solo audio) → videoSpec nil: el .mov sale solo con pistas de audio.

        // 3. Writer con SOLO las pistas de las fuentes activadas.
        let writer = try MovieWriter(
            outputURL: config.outputURL,
            video: videoSpec,
            includeMicrophone: config.capturesMicrophone,
            includeSystemAudio: config.capturesSystemAudio)

        // 4. Cablear el pipeline. Las closures capturan writer/compositor
        //    directamente (no self) para que las colas de captura no toquen
        //    estado del motor.
        let usePiP = config.capturesScreen && config.capturesCamera
        let latestCameraFrame = LatestFrameBox()

        if let camera {
            if usePiP {
                camera.onFrame = { pixelBuffer, _ in
                    // En PiP la cámara no marca el ritmo: solo deja su frame
                    // más reciente para que lo estampe el frame de pantalla.
                    latestCameraFrame.value = pixelBuffer
                }
            } else {
                // Cámara sin pantalla → la cámara ES el video (pantalla completa).
                camera.onFrame = { pixelBuffer, pts in
                    writer.appendVideo(pixelBuffer: pixelBuffer, presentationTime: pts)
                }
            }
        }

        var screen: ScreenCapturer?
        if config.capturesScreen || config.capturesSystemAudio {
            let scr = ScreenCapturer()
            if config.capturesScreen {
                if usePiP, let spec = videoSpec {
                    let compositor = PiPCompositor(width: spec.width, height: spec.height)
                    scr.onVideoFrame = { screenBuffer, pts in
                        // Composición en la cola de video de SCStream (GPU);
                        // el append se serializa dentro del writer.
                        if let composed = compositor.compose(screen: screenBuffer, camera: latestCameraFrame.value) {
                            writer.appendVideo(pixelBuffer: composed, presentationTime: pts)
                        }
                    }
                } else {
                    scr.onVideoFrame = { screenBuffer, pts in
                        writer.appendVideo(pixelBuffer: screenBuffer, presentationTime: pts)
                    }
                }
            }
            if config.capturesSystemAudio {
                scr.onSystemAudio = { sample in
                    writer.appendSystemAudio(sample)
                }
            }
            scr.onFatalError = { [weak self] error in
                Task { await self?.handleFatalError(error) }
            }
            screen = scr
        }

        var mic: MicrophoneCapturer?
        if config.capturesMicrophone {
            let m = MicrophoneCapturer()
            try m.configure(deviceID: config.microphoneDeviceID)
            m.onAudio = { sample in
                writer.appendMicrophone(sample)
            }
            mic = m
        }

        // 5. Arrancar todo. Si algo falla aquí, el catch de start() limpia.
        self.writer = writer
        self.cameraCapturer = camera
        self.micCapturer = mic
        self.screenCapturer = screen

        await mic?.start()
        await camera?.start()
        if let screen {
            try await screen.start(
                displayID: config.displayID,
                targetWidth: config.targetWidth,
                fps: config.framesPerSecond,
                captureVideo: config.capturesScreen,
                captureAudio: config.capturesSystemAudio)
        }
    }

    // MARK: - Stop

    /// Detiene la grabación y devuelve la URL del archivo finalizado.
    @discardableResult
    public func stop() async throws -> URL {
        guard case .recording = state else {
            throw RecordingError.estadoInvalido("no hay ninguna grabación en curso")
        }
        setState(.stopping)

        // Orden: primero paran las fuentes (dejan de llegar buffers), después
        // se finaliza el writer — así el archivo queda siempre reproducible.
        await teardownCapturers()

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

    private func handleFatalError(_ error: Error) async {
        guard case .recording = state else { return }
        setState(.stopping)
        await teardownCapturers()
        // Intentar salvar lo grabado hasta ahora: el archivo queda finalizado.
        if let writer {
            self.writer = nil
            _ = try? await writer.finish()
        }
        setState(.failed(.capturaInterrumpida(error.localizedDescription)))
    }

    private func teardownCapturers() async {
        await screenCapturer?.stop()
        await cameraCapturer?.stop()
        await micCapturer?.stop()
        screenCapturer = nil
        cameraCapturer = nil
        micCapturer = nil
    }

    private func setState(_ newState: RecordingState) {
        if Thread.isMainThread {
            state = newState
        } else {
            DispatchQueue.main.sync { self.state = newState }
        }
    }
}
