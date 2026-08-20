import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreGraphics

/// Captura pantalla/ventana/región y/o audio del sistema con ScreenCaptureKit.
///
/// Uso: `prepare(...)` resuelve el filtro y devuelve el tamaño de salida
/// (el motor lo necesita ANTES de crear el writer/compositor); `start()`
/// arranca el stream.
///
/// Notas:
/// - El audio del sistema se captura con el MISMO SCStream que el video.
///   Cuando solo se pide audio, no registramos la salida de video y pedimos
///   frames mínimos.
/// - Las ventanas de la propia app (controles flotantes, vista previa) se
///   excluyen de la captura de pantalla/región vía `excludingApplications`.
///   En captura de ventana no aplica: solo se ve la ventana elegida.
final class ScreenCapturer: NSObject, SCStreamOutput, SCStreamDelegate {
    var onVideoFrame: ((CVPixelBuffer, CMTime) -> Void)?
    var onSystemAudio: ((CMSampleBuffer) -> Void)?
    /// El stream se detuvo solo (p. ej. permiso revocado o ventana cerrada).
    var onFatalError: ((Error) -> Void)?

    private var stream: SCStream?
    private var filter: SCContentFilter?
    private var configuration: SCStreamConfiguration?
    private let videoQueue = DispatchQueue(label: "record.screen.video")
    private let audioQueue = DispatchQueue(label: "record.screen.audio")
    private var stopping = false

    private(set) var outputSize: (width: Int, height: Int) = (2, 2)

    /// Resuelve el target contra el contenido compartible, arma filtro y
    /// configuración, y devuelve el tamaño de salida del video.
    func prepare(target: CaptureTarget,
                 targetWidth: Int,
                 fps: Int,
                 captureVideo: Bool,
                 captureAudio: Bool) async throws -> (width: Int, height: Int) {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw RecordingError.permisoPantallaDenegado
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == ownPID }

        func resolveDisplay(_ id: CGDirectDisplayID?) throws -> SCDisplay {
            let wanted = id ?? CGMainDisplayID()
            guard let display = content.displays.first(where: { $0.displayID == wanted }) ?? content.displays.first else {
                throw RecordingError.pantallaNoEncontrada
            }
            return display
        }

        /// Tamaño par que respeta el aspecto, con `targetWidth` como ancho
        /// máximo (contenido más angosto se captura a 2x nativo por nitidez).
        func fittedSize(pointWidth: CGFloat, pointHeight: CGFloat) -> (Int, Int) {
            guard pointWidth > 0, pointHeight > 0 else { return (targetWidth, targetWidth * 9 / 16) }
            let pixelWidth = min(CGFloat(targetWidth), pointWidth * 2)
            var w = Int(pixelWidth.rounded()); w -= w % 2
            var h = Int((pixelWidth * pointHeight / pointWidth).rounded()); h -= h % 2
            return (max(w, 2), max(h, 2))
        }

        let filter: SCContentFilter
        var size = (width: 2, height: 2)

        switch target {
        case .display(let id):
            let display = try resolveDisplay(id)
            filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            size = fittedSize(pointWidth: CGFloat(display.width), pointHeight: CGFloat(display.height))
        case .window(let windowID):
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw RecordingError.ventanaNoEncontrada
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            size = fittedSize(pointWidth: window.frame.width, pointHeight: window.frame.height)
        case .region(let id, let rect):
            guard rect.width >= 16, rect.height >= 16 else { throw RecordingError.regionInvalida }
            let display = try resolveDisplay(id)
            filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            size = fittedSize(pointWidth: rect.width, pointHeight: rect.height)
        }

        let config = SCStreamConfiguration()
        if captureVideo {
            config.width = size.width
            config.height = size.height
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = true
            config.queueDepth = 6
            if case .region(_, let rect) = target {
                config.sourceRect = rect
            }
        } else {
            // Solo audio del sistema: stream de video mínimo que ignoramos.
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 5)
            size = (2, 2)
        }
        if captureAudio {
            config.capturesAudio = true
            config.sampleRate = 48_000
            config.channelCount = 2
            config.excludesCurrentProcessAudio = true
        }

        self.filter = filter
        self.configuration = config
        self.outputSize = size
        return size
    }

    /// Arranca la captura. Requiere `prepare(...)` previo.
    func start(captureVideo: Bool, captureAudio: Bool) async throws {
        guard let filter, let configuration else {
            throw RecordingError.estadoInvalido("ScreenCapturer.start sin prepare previo")
        }
        stopping = false
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
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
