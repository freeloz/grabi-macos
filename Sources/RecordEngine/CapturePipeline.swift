import Foundation
import AVFoundation
import CoreVideo

/// Caja thread-safe para "el último frame de cámara". La cola de la cámara
/// escribe y la cola de pantalla lee (para el compositing PiP).
final class LatestFrameBox {
    private let lock = NSLock()
    private var buffer: CVPixelBuffer?

    var value: CVPixelBuffer? {
        get { lock.lock(); defer { lock.unlock() }; return buffer }
        set { lock.lock(); defer { lock.unlock() }; buffer = newValue }
    }
}

/// Pipeline de captura y composición compartido entre la vista previa y la
/// grabación: los MISMOS capturadores y el MISMO compositor alimentan ambas,
/// de modo que la vista previa muestra exactamente lo que se graba y empezar
/// a grabar no duplica trabajo (solo "engancha" un writer al flujo).
///
/// El micrófono NO vive aquí: solo se captura mientras se graba (encenderlo
/// durante la vista previa activaría el indicador de micrófono del sistema
/// sin necesidad).
final class CapturePipeline {
    let config: RecordingConfiguration
    /// Tamaño del lienzo de video; nil si la configuración no tiene video.
    private(set) var canvasSize: (width: Int, height: Int)?

    private var screen: ScreenCapturer?
    private var camera: CameraCapturer?
    private var compositor: PiPCompositor?
    private let latestCameraFrame = LatestFrameBox()

    // El writer se engancha/desengancha en caliente; las colas de captura lo
    // leen en cada buffer.
    private let sinkLock = NSLock()
    private var _writer: MovieWriter?
    private var _onPreviewFrame: ((CVPixelBuffer) -> Void)?

    var onFatalError: ((Error) -> Void)?
    /// Nivel RMS del audio del sistema (cola de audio de SCStream).
    var onSystemAudioLevel: ((Double) -> Void)?

    private var running = false

    init(config: RecordingConfiguration) {
        self.config = config
    }

    private var writer: MovieWriter? {
        sinkLock.lock(); defer { sinkLock.unlock() }; return _writer
    }

    var onPreviewFrame: ((CVPixelBuffer) -> Void)? {
        get { sinkLock.lock(); defer { sinkLock.unlock() }; return _onPreviewFrame }
        set { sinkLock.lock(); defer { sinkLock.unlock() }; _onPreviewFrame = newValue }
    }

    func attachWriter(_ writer: MovieWriter) {
        sinkLock.lock(); defer { sinkLock.unlock() }
        _writer = writer
    }

    func detachWriter() {
        sinkLock.lock(); defer { sinkLock.unlock() }
        _writer = nil
    }

    /// Forma/posición/tamaño de la cámara, aplicable en vivo.
    func updateCameraLayout(_ layout: CameraLayout) {
        compositor?.layout = layout
    }

    /// ¿Esta configuración produce el mismo pipeline de captura? (el mic y el
    /// bitrate no afectan al pipeline; sí las fuentes de video/audio-sistema,
    /// el target y la resolución)
    func isCompatible(with other: RecordingConfiguration) -> Bool {
        config.capturesScreen == other.capturesScreen
            && config.capturesCamera == other.capturesCamera
            && config.capturesSystemAudio == other.capturesSystemAudio
            && config.target == other.target
            && config.targetWidth == other.targetWidth
            && config.framesPerSecond == other.framesPerSecond
            && config.cameraDeviceID == other.cameraDeviceID
    }

    // MARK: - Arranque

    /// Configura capturadores y compositor y arranca la captura.
    func start() async throws {
        guard !running else { return }

        // 1. Cámara primero (sin arrancarla) para conocer sus dimensiones.
        if config.capturesCamera {
            let cam = CameraCapturer()
            try cam.configure(deviceID: config.cameraDeviceID)
            camera = cam
        }

        // 2. Pantalla/región/ventana + audio de sistema.
        if config.capturesScreen || config.capturesSystemAudio {
            let scr = ScreenCapturer()
            let size = try await scr.prepare(
                target: config.target,
                targetWidth: config.targetWidth,
                fps: config.framesPerSecond,
                captureVideo: config.capturesScreen,
                captureAudio: config.capturesSystemAudio)
            screen = scr
            if config.capturesScreen {
                canvasSize = size
            }
        }
        if !config.capturesScreen, let camera {
            canvasSize = camera.dimensions
        }

        // 3. Compositor: en modo PiP (pantalla + cámara) y también en captura
        //    de ventana sin cámara, porque ahí hay que recortar el contentRect
        //    (SCStream no llena el buffer con la ventana).
        var needsCompositor = config.capturesScreen && config.capturesCamera
        if case .window = config.target, config.capturesScreen { needsCompositor = true }
        if needsCompositor, let size = canvasSize {
            compositor = PiPCompositor(width: size.width, height: size.height, layout: config.cameraLayout)
        }

        wireCallbacks()

        // 4. Arrancar.
        await camera?.start()
        if let screen {
            do {
                try await screen.start(
                    captureVideo: config.capturesScreen,
                    captureAudio: config.capturesSystemAudio)
            } catch {
                await stop()
                throw error
            }
        }
        running = true
    }

    private func wireCallbacks() {
        let box = latestCameraFrame

        if let camera {
            if compositor != nil {
                camera.onFrame = { pixelBuffer, _ in
                    // En PiP la cámara no marca el ritmo: solo deja su frame
                    // más reciente para que lo estampe el frame de pantalla.
                    box.value = pixelBuffer
                }
            } else {
                // Cámara sin pantalla → la cámara ES el video, a pantalla
                // completa y en modo espejo (como toda selfie).
                let mirror = MirrorRenderer(width: camera.dimensions.width,
                                            height: camera.dimensions.height)
                camera.onFrame = { [weak self] pixelBuffer, pts in
                    guard let self, let mirrored = mirror.mirrored(pixelBuffer) else { return }
                    self.writer?.appendVideo(pixelBuffer: mirrored, presentationTime: pts)
                    self.onPreviewFrame?(mirrored)
                }
            }
        }

        if let screen {
            if config.capturesScreen {
                if let compositor {
                    // La cámara tarda ~1 s en arrancar (auto-exposición). Para
                    // que la grabación no empiece con el PiP congelado o
                    // apareciendo de golpe, no se escribe video hasta que la
                    // cámara entrega su primer frame (tope: 45 frames ≈ 1,5 s
                    // por si la cámara falla). Si hubo vista previa antes, la
                    // cámara ya está caliente y esto no espera nada.
                    let waitsForCamera = config.capturesCamera
                    var framesWaitingForCamera = 0 // solo se toca en la cola de video
                    screen.onVideoFrame = { [weak self] screenBuffer, pts, contentRect in
                        guard let self else { return }
                        let cameraFrame = box.value
                        // Composición en la cola de video de SCStream (GPU);
                        // el mismo frame compuesto va a writer y vista previa.
                        guard let composed = compositor.compose(screen: screenBuffer,
                                                                screenContentRect: contentRect,
                                                                camera: cameraFrame) else { return }
                        self.onPreviewFrame?(composed)
                        if waitsForCamera, cameraFrame == nil, self.writer != nil, framesWaitingForCamera < 45 {
                            framesWaitingForCamera += 1
                            return
                        }
                        self.writer?.appendVideo(pixelBuffer: composed, presentationTime: pts)
                    }
                } else {
                    screen.onVideoFrame = { [weak self] screenBuffer, pts, _ in
                        guard let self else { return }
                        self.writer?.appendVideo(pixelBuffer: screenBuffer, presentationTime: pts)
                        self.onPreviewFrame?(screenBuffer)
                    }
                }
            }
            if config.capturesSystemAudio {
                screen.onSystemAudio = { [weak self] sample in
                    guard let self else { return }
                    self.writer?.appendSystemAudio(sample)
                    if let onLevel = self.onSystemAudioLevel,
                       let level = AudioLevel.normalizedLevel(from: sample) {
                        onLevel(level)
                    }
                }
            }
            screen.onFatalError = { [weak self] error in
                self?.onFatalError?(error)
            }
        }
    }

    func stop() async {
        running = false
        detachWriter()
        await screen?.stop()
        await camera?.stop()
        screen = nil
        camera = nil
        compositor = nil
        latestCameraFrame.value = nil
    }
}
