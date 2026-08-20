import Foundation
import CoreGraphics

/// Fuentes de grabación disponibles.
public enum RecordingSource: String, CaseIterable, Identifiable, Sendable {
    case screen
    case camera
    case microphone
    case systemAudio

    public var id: String { rawValue }

    /// Nombre para mostrar en la UI.
    public var displayName: String {
        switch self {
        case .screen: return "Pantalla"
        case .camera: return "Cámara"
        case .microphone: return "Micrófono"
        case .systemAudio: return "Audio del sistema"
        }
    }
}

/// Configuración de una grabación. Cada fuente es un toggle independiente;
/// la única restricción es que al menos una esté activa.
public struct RecordingConfiguration: Sendable {
    public var capturesScreen: Bool
    public var capturesCamera: Bool
    public var capturesMicrophone: Bool
    public var capturesSystemAudio: Bool

    /// Archivo .mov de salida.
    public var outputURL: URL

    /// Ancho objetivo del video de pantalla. El alto se deriva del aspecto
    /// real de la pantalla para no deformar la imagen (los MacBook son 16:10,
    /// no 16:9, así que forzar 1920x1080 estiraría el video).
    public var targetWidth: Int
    public var framesPerSecond: Int
    public var videoBitrate: Int

    /// Pantalla a grabar; nil → pantalla principal.
    public var displayID: CGDirectDisplayID?
    /// uniqueID de AVCaptureDevice; nil → dispositivo por defecto.
    public var cameraDeviceID: String?
    public var microphoneDeviceID: String?

    public var hasAnySource: Bool {
        capturesScreen || capturesCamera || capturesMicrophone || capturesSystemAudio
    }

    public var hasVideo: Bool { capturesScreen || capturesCamera }

    public init(
        capturesScreen: Bool = true,
        capturesCamera: Bool = true,
        capturesMicrophone: Bool = true,
        capturesSystemAudio: Bool = true,
        outputURL: URL,
        targetWidth: Int = 1920,
        framesPerSecond: Int = 30,
        videoBitrate: Int = 8_000_000,
        displayID: CGDirectDisplayID? = nil,
        cameraDeviceID: String? = nil,
        microphoneDeviceID: String? = nil
    ) {
        self.capturesScreen = capturesScreen
        self.capturesCamera = capturesCamera
        self.capturesMicrophone = capturesMicrophone
        self.capturesSystemAudio = capturesSystemAudio
        self.outputURL = outputURL
        self.targetWidth = targetWidth
        self.framesPerSecond = framesPerSecond
        self.videoBitrate = videoBitrate
        self.displayID = displayID
        self.cameraDeviceID = cameraDeviceID
        self.microphoneDeviceID = microphoneDeviceID
    }
}
