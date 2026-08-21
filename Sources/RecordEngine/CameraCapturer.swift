import Foundation
import AVFoundation
import CoreVideo

/// Captura la cámara con AVFoundation y entrega píxeles BGRA sin comprimir.
final class CameraCapturer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "record.camera")
    /// Dimensiones reales que entregará la cámara; disponibles tras `configure()`.
    private(set) var dimensions: (width: Int, height: Int) = (1280, 720)

    /// Configura la sesión SIN arrancarla, para que el motor conozca las
    /// dimensiones reales antes de crear el writer (en modo cámara-sola el
    /// tamaño del video de salida es el de la cámara).
    func configure(deviceID: String?) throws {
        let device: AVCaptureDevice?
        if let deviceID {
            device = AVCaptureDevice(uniqueID: deviceID)
        } else {
            device = AVCaptureDevice.default(for: .video)
        }
        guard let device else { throw RecordingError.cameraUnavailable }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw RecordingError.cameraPermissionDenied
        }
        guard session.canAddInput(input) else { throw RecordingError.cameraUnavailable }
        session.addInput(input)

        // Preferimos 1080p; si la cámara no lo soporta (FaceTime 720p), caemos a 720p.
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
            dimensions = (1920, 1080)
        } else if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
            dimensions = (1280, 720)
        }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        // Descartar frames tardíos: en PiP solo interesa el más reciente y en
        // cámara-sola preferimos saltar un frame antes que acumular latencia.
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw RecordingError.cameraUnavailable }
        session.addOutput(output)
    }

    /// `startRunning` bloquea; se llama fuera del main thread.
    func start() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                session.startRunning()
                continuation.resume()
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if session.isRunning { session.stopRunning() }
                continuation.resume()
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }
}
