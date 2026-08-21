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
        case .screen: return L("source.screen")
        case .camera: return L("source.camera")
        case .microphone: return L("source.microphone")
        case .systemAudio: return L("source.systemAudio")
        }
    }
}

/// Forma de la cámara en el video (según el sistema de diseño: círculo,
/// cuadrado o rectángulo 3:2; cuadrado y rectángulo con esquinas redondeadas).
public enum CameraShape: String, CaseIterable, Identifiable, Sendable {
    case circle
    case square
    case rectangle

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .circle: return L("shape.circle")
        case .square: return L("shape.square")
        case .rectangle: return L("shape.rectangle")
        }
    }

    /// Relación ancho/alto de la forma (del prototipo: rect = 1,5 × alto).
    public var aspectRatio: CGFloat {
        self == .rectangle ? 1.5 : 1.0
    }
}

/// Posición/tamaño/forma de la cámara sobre el lienzo, en coordenadas
/// normalizadas (0–1) para que la misma configuración sirva en la vista
/// previa y en el video grabado. Modificable EN VIVO durante la grabación.
public struct CameraLayout: Equatable, Sendable {
    public var shape: CameraShape
    /// Esquina superior izquierda, normalizada: x sobre el ancho del lienzo,
    /// y sobre el alto.
    public var origin: CGPoint
    /// Alto normalizado sobre el alto del lienzo. El ancho se deriva de la forma.
    public var height: CGFloat

    /// Valor por defecto del prototipo aprobado: círculo, abajo a la derecha
    /// (cam {x:486, y:206, s:130} sobre un lienzo de 640×360).
    public static let `default` = CameraLayout(
        shape: .circle,
        origin: CGPoint(x: 486.0 / 640.0, y: 206.0 / 360.0),
        height: 130.0 / 360.0)

    public init(shape: CameraShape, origin: CGPoint, height: CGFloat) {
        self.shape = shape
        self.origin = origin
        self.height = height
    }

    /// Radio de esquina relativo al alto (del prototipo: radius 12 con s=130).
    public var cornerRadiusFraction: CGFloat {
        shape == .circle ? 0.5 : 12.0 / 130.0
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

    /// Qué capturar: pantalla completa, ventana o región.
    public var target: CaptureTarget
    /// Forma/posición/tamaño de la cámara (PiP). Modificable en vivo.
    public var cameraLayout: CameraLayout
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
        target: CaptureTarget = .mainDisplay,
        cameraLayout: CameraLayout = .default,
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
        self.target = target
        self.cameraLayout = cameraLayout
        self.cameraDeviceID = cameraDeviceID
        self.microphoneDeviceID = microphoneDeviceID
    }
}
