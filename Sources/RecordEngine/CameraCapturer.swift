import Foundation
import AVFoundation
import CoreVideo
import GrabiDomain

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
    /// - Parameters:
    ///   - preferredHeight: 1080 when the camera IS the video; 720 is plenty
    ///     for a PiP that occupies a corner — and halves the work macOS does
    ///     per frame (Center Stage / Reactions run Vision on every frame).
    ///   - fps: caps the camera's frame rate to the pipeline's, so we don't
    ///     pay for 30 fps of face detection to feed a 10 fps preview.
    func configure(deviceID: String?, preferredHeight: Int = 1080, fps: Int = 30) throws {
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

        if preferredHeight >= 1080, session.canSetSessionPreset(.hd1920x1080) {
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

        // Cap the frame rate to what the pipeline consumes. This has to come
        // AFTER addOutput: attaching an output resets the format's frame
        // duration, so doing it earlier silently does nothing (macOS keeps
        // running the camera — and its per-frame Vision work — at 30 fps).
        if let range = device.activeFormat.videoSupportedFrameRateRanges.first {
            let target = Double(max(1, fps))
            let clamped = min(max(target, range.minFrameRate), range.maxFrameRate)
            if (try? device.lockForConfiguration()) != nil {
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(clamped.rounded()))
                device.unlockForConfiguration()
            }
        }
        // Many built-in cameras only offer 30–30 fps, so the device-level cap
        // above is a no-op there and macOS keeps its own per-frame work at 30.
        // The connection cap always applies: frames we would not use never
        // reach the compositor.
        if let connection = output.connection(with: .video) {
            connection.videoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, fps)))
        }
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
