import Foundation
import AVFoundation

/// Captures the microphone with AVFoundation and delivers PCM buffers.
final class MicrophoneCapturer: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    var onAudio: ((CMSampleBuffer) -> Void)?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "record.microphone")

    /// The microphone's native channels (after `configure`). The mic's AAC
    /// track is created with this count: forcing a mono mic to stereo makes
    /// the downmix split/attenuate the signal and sound very quiet.
    private(set) var nativeChannelCount = 2

    func configure(deviceID: String?) throws {
        let device: AVCaptureDevice?
        if let deviceID {
            device = AVCaptureDevice(uniqueID: deviceID)
        } else {
            device = AVCaptureDevice.default(for: .audio)
        }
        guard let device else { throw RecordingError.microphoneUnavailable }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw RecordingError.microphonePermissionDenied
        }
        guard session.canAddInput(input) else { throw RecordingError.microphoneUnavailable }
        session.addInput(input)

        if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(device.activeFormat.formatDescription) {
            let channels = Int(asbd.pointee.mChannelsPerFrame)
            nativeChannelCount = (1...2).contains(channels) ? channels : 2
        }

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw RecordingError.microphoneUnavailable }
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
