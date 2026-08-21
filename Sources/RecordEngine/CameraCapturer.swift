import Foundation
import AVFoundation
import CoreVideo

/// Captures the camera with AVFoundation and delivers uncompressed BGRA pixels.
final class CameraCapturer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "record.camera")
    /// Actual dimensions the camera will deliver; available after `configure()`.
    private(set) var dimensions: (width: Int, height: Int) = (1280, 720)

    /// Configures the session WITHOUT starting it, so the engine knows the
    /// actual dimensions before creating the writer (in camera-only mode the
    /// output video size is the camera's).
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

        // Prefer 1080p; if the camera doesn't support it (FaceTime 720p), fall back to 720p.
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
            dimensions = (1920, 1080)
        } else if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
            dimensions = (1280, 720)
        }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        // Discard late frames: in PiP only the most recent one matters, and in
        // camera-only mode we'd rather skip a frame than accumulate latency.
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw RecordingError.cameraUnavailable }
        session.addOutput(output)
    }

    /// `startRunning` blocks; it is called off the main thread.
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
