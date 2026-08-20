import Foundation
import AVFoundation

/// Captura el micrófono con AVFoundation y entrega buffers PCM.
final class MicrophoneCapturer: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    var onAudio: ((CMSampleBuffer) -> Void)?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "record.microphone")

    func configure(deviceID: String?) throws {
        let device: AVCaptureDevice?
        if let deviceID {
            device = AVCaptureDevice(uniqueID: deviceID)
        } else {
            device = AVCaptureDevice.default(for: .audio)
        }
        guard let device else { throw RecordingError.microfonoNoDisponible }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw RecordingError.permisoMicrofonoDenegado
        }
        guard session.canAddInput(input) else { throw RecordingError.microfonoNoDisponible }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw RecordingError.microfonoNoDisponible }
        session.addOutput(output)
    }

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
        onAudio?(sampleBuffer)
    }
}
