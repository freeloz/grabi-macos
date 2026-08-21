import Foundation
import AVFoundation
import CoreVideo

/// Thread-safe box for "the latest camera frame". The camera queue
/// writes and the screen queue reads (for PiP compositing).
final class LatestFrameBox {
    private let lock = NSLock()
    private var buffer: CVPixelBuffer?

    var value: CVPixelBuffer? {
        get { lock.lock(); defer { lock.unlock() }; return buffer }
        set { lock.lock(); defer { lock.unlock() }; buffer = newValue }
    }
}

/// Capture and compositing pipeline shared between the preview and the
/// recording: the SAME capturers and the SAME compositor feed both, so
/// the preview shows exactly what gets recorded and starting a recording
/// duplicates no work (it just "hooks" a writer onto the flow).
///
/// The microphone does NOT live here: it's only captured while recording
/// (turning it on during the preview would light up the system's
/// microphone indicator needlessly).
final class CapturePipeline {
    let config: RecordingConfiguration
    /// Size of the video canvas; nil if the configuration has no video.
    private(set) var canvasSize: (width: Int, height: Int)?

    private var screen: ScreenCapturer?
    private var camera: CameraCapturer?
    private var compositor: PiPCompositor?
    private let latestCameraFrame = LatestFrameBox()

    // The writer is attached/detached on the fly; the capture queues read
    // it on every buffer.
    private let sinkLock = NSLock()
    private var _writer: MovieWriter?
    private var _onPreviewFrame: ((CVPixelBuffer) -> Void)?

    var onFatalError: ((Error) -> Void)?
    /// RMS level of the system audio (SCStream's audio queue).
    var onSystemAudioLevel: ((Double) -> Void)?
    /// Raw camera frames (no mirror or shape), for the floating selfie
    /// box during recording. Camera queue.
    var onCameraFrame: ((CVPixelBuffer) -> Void)?

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

    /// Shape/position/size of the camera, applicable live.
    func updateCameraLayout(_ layout: CameraLayout) {
        compositor?.layout = layout
    }

    /// Turns the camera off/on LIVE (PiP mode only: with screen).
    /// Turning off stops the session (the camera light goes off) and clears
    /// the latest frame → the compositor stops stamping the PiP.
    func setCameraHidden(_ hidden: Bool) async {
        guard config.capturesCamera, config.capturesScreen else { return }
        if hidden {
            await camera?.stop()
            latestCameraFrame.value = nil
        } else {
            await camera?.start()
        }
    }

    /// Does this configuration produce the same capture pipeline? (mic and
    /// bitrate don't affect the pipeline; the video/system-audio sources,
    /// target and resolution do)
    func isCompatible(with other: RecordingConfiguration) -> Bool {
        config.capturesScreen == other.capturesScreen
            && config.capturesCamera == other.capturesCamera
            && config.capturesSystemAudio == other.capturesSystemAudio
            && config.target == other.target
            && config.targetWidth == other.targetWidth
            && config.framesPerSecond == other.framesPerSecond
            && config.cameraDeviceID == other.cameraDeviceID
    }

    // MARK: - Startup

    /// Configures capturers and compositor and starts the capture.
    func start() async throws {
        guard !running else { return }

        // 1. Camera first (without starting it) to learn its dimensions.
        if config.capturesCamera {
            let cam = CameraCapturer()
            try cam.configure(deviceID: config.cameraDeviceID)
            camera = cam
        }

        // 2. Display/region/window + system audio.
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

        // 3. Compositor: in PiP mode (screen + camera) and also in window
        //    capture without camera, because there the contentRect must be
        //    cropped (SCStream doesn't fill the buffer with the window).
        var needsCompositor = config.capturesScreen && config.capturesCamera
        if case .window = config.target, config.capturesScreen { needsCompositor = true }
        if needsCompositor, let size = canvasSize {
            compositor = PiPCompositor(width: size.width, height: size.height, layout: config.cameraLayout)
        }

        wireCallbacks()

        // 4. Start.
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
                camera.onFrame = { [weak self] pixelBuffer, _ in
                    // In PiP the camera doesn't set the pace: it just leaves
                    // its latest frame for the screen frame to stamp.
                    box.value = pixelBuffer
                    self?.onCameraFrame?(pixelBuffer)
                }
            } else {
                // Camera without screen → the camera IS the video, full
                // frame and mirrored (like every selfie).
                let mirror = MirrorRenderer(width: camera.dimensions.width,
                                            height: camera.dimensions.height)
                camera.onFrame = { [weak self] pixelBuffer, pts in
                    guard let self, let mirrored = mirror.mirrored(pixelBuffer) else { return }
                    self.writer?.appendVideo(pixelBuffer: mirrored, presentationTime: pts)
                    self.onPreviewFrame?(mirrored)
                    self.onCameraFrame?(pixelBuffer)
                }
            }
        }

        if let screen {
            if config.capturesScreen {
                if let compositor {
                    // The camera takes ~1 s to start (auto-exposure). So the
                    // recording doesn't open with the PiP frozen or popping
                    // in abruptly, no video is written until the camera
                    // delivers its first frame (cap: 45 frames ≈ 1.5 s in
                    // case the camera fails). If a preview ran before, the
                    // camera is already warm and this waits for nothing.
                    let waitsForCamera = config.capturesCamera
                    var framesWaitingForCamera = 0 // only touched on the video queue
                    var cameraSeen = false // the wait applies ONLY at startup:
                    // if the camera is later hidden live, the video must not pause
                    screen.onVideoFrame = { [weak self] screenBuffer, pts, contentRect in
                        guard let self else { return }
                        let cameraFrame = box.value
                        if cameraFrame != nil { cameraSeen = true }
                        // Compositing on SCStream's video queue (GPU); the
                        // same composed frame goes to writer and preview.
                        guard let composed = compositor.compose(screen: screenBuffer,
                                                                screenContentRect: contentRect,
                                                                camera: cameraFrame) else { return }
                        self.onPreviewFrame?(composed)
                        if waitsForCamera, !cameraSeen, self.writer != nil, framesWaitingForCamera < 45 {
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
