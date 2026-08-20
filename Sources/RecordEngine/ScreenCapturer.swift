import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreGraphics

/// Captura pantalla y/o audio del sistema con ScreenCaptureKit (SCStream).
///
/// Nota: el audio del sistema se captura con el MISMO SCStream que el video.
/// Cuando solo se pide audio del sistema (sin pantalla), igualmente hay que
/// crear el stream con un filtro de pantalla; simplemente no registramos la
/// salida de video y pedimos frames mínimos para no gastar recursos.
final class ScreenCapturer: NSObject, SCStreamOutput, SCStreamDelegate {
    var onVideoFrame: ((CVPixelBuffer, CMTime) -> Void)?
    var onSystemAudio: ((CMSampleBuffer) -> Void)?
    /// El stream se detuvo solo (p. ej. permiso revocado a mitad de grabación).
    var onFatalError: ((Error) -> Void)?

    private var stream: SCStream?
    private let videoQueue = DispatchQueue(label: "record.screen.video")
    private let audioQueue = DispatchQueue(label: "record.screen.audio")
    private var stopping = false

    /// Tamaño de salida (par, respetando el aspecto real de la pantalla) que
    /// tendrá el video para un ancho objetivo dado. El motor lo usa para crear
    /// el writer ANTES de arrancar el stream.
    static func outputSize(displayID: CGDirectDisplayID?, targetWidth: Int) -> (width: Int, height: Int) {
        let id = displayID ?? CGMainDisplayID()
        let bounds = CGDisplayBounds(id)
        guard bounds.width > 0, bounds.height > 0 else { return (targetWidth, targetWidth * 9 / 16) }
        let aspect = bounds.height / bounds.width
        var height = Int((CGFloat(targetWidth) * aspect).rounded())
        height -= height % 2 // los encoders quieren dimensiones pares
        return (targetWidth, height)
    }

    func start(displayID: CGDirectDisplayID?,
               targetWidth: Int,
               fps: Int,
               captureVideo: Bool,
               captureAudio: Bool) async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            // SCShareableContent falla típicamente por falta de permiso.
            throw RecordingError.permisoPantallaDenegado
        }

        let wantedID = displayID ?? CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == wantedID }) ?? content.displays.first else {
            throw RecordingError.capturaInterrumpida("no se encontró ninguna pantalla para capturar")
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()

        if captureVideo {
            let size = Self.outputSize(displayID: display.displayID, targetWidth: targetWidth)
            config.width = size.width
            config.height = size.height
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = true
            config.queueDepth = 6
        } else {
            // Solo audio del sistema: stream de video mínimo que ignoramos.
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 5)
        }

        if captureAudio {
            config.capturesAudio = true
            config.sampleRate = 48_000
            config.channelCount = 2
            config.excludesCurrentProcessAudio = true
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        if captureVideo {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        }
        if captureAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        }

        do {
            try await stream.startCapture()
        } catch {
            throw RecordingError.capturaInterrumpida("no se pudo iniciar la captura de pantalla: \(error.localizedDescription)")
        }
        self.stream = stream
    }

    func stop() async {
        stopping = true
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .screen:
            // SCStream emite también frames "idle"/incompletos sin imagen;
            // solo interesan los completos.
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let statusRaw = attachments.first?[.status] as? Int,
                  statusRaw == SCFrameStatus.complete.rawValue,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
            else { return }
            onVideoFrame?(pixelBuffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        case .audio:
            onSystemAudio?(sampleBuffer)
        default:
            // .microphone (macOS 15+) no se usa: el mic va por AVFoundation.
            break
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard !stopping else { return }
        onFatalError?(error)
    }
}
