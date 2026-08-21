import Foundation
import CoreGraphics

/// Available recording sources.
public enum RecordingSource: String, CaseIterable, Identifiable, Sendable {
    case screen
    case camera
    case microphone
    case systemAudio

    public var id: String { rawValue }

    /// Display name for the UI.
    public var displayName: String {
        switch self {
        case .screen: return L("source.screen")
        case .camera: return L("source.camera")
        case .microphone: return L("source.microphone")
        case .systemAudio: return L("source.systemAudio")
        }
    }
}

/// Shape of the camera in the video (per the design system: circle,
/// square, or 3:2 rectangle; square and rectangle with rounded corners).
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

    /// Width/height ratio of the shape (from the prototype: rect = 1.5 × height).
    public var aspectRatio: CGFloat {
        self == .rectangle ? 1.5 : 1.0
    }
}

/// Position/size/shape of the camera over the canvas, in normalized
/// coordinates (0–1) so the same configuration works for the live
/// preview and the recorded video. Modifiable LIVE while recording.
public struct CameraLayout: Equatable, Sendable {
    public var shape: CameraShape
    /// Top-left corner, normalized: x over the canvas width,
    /// y over the height.
    public var origin: CGPoint
    /// Height normalized over the canvas height. Width is derived from the shape.
    public var height: CGFloat

    /// Default value from the approved prototype: circle, bottom right
    /// (cam {x:486, y:206, s:130} over a 640×360 canvas).
    public static let `default` = CameraLayout(
        shape: .circle,
        origin: CGPoint(x: 486.0 / 640.0, y: 206.0 / 360.0),
        height: 130.0 / 360.0)

    public init(shape: CameraShape, origin: CGPoint, height: CGFloat) {
        self.shape = shape
        self.origin = origin
        self.height = height
    }

    /// Corner radius relative to the height (from the prototype: radius 12 at s=130).
    public var cornerRadiusFraction: CGFloat {
        shape == .circle ? 0.5 : 12.0 / 130.0
    }
}

/// Configuration of a recording. Each source is an independent toggle;
/// the only restriction is that at least one is active.
public struct RecordingConfiguration: Sendable {
    public var capturesScreen: Bool
    public var capturesCamera: Bool
    public var capturesMicrophone: Bool
    public var capturesSystemAudio: Bool

    /// Output .mov file.
    public var outputURL: URL

    /// Target width of the screen video. The height is derived from the
    /// display's real aspect so the image is not distorted (MacBooks are
    /// 16:10, not 16:9, so forcing 1920x1080 would stretch the video).
    public var targetWidth: Int
    public var framesPerSecond: Int
    public var videoBitrate: Int

    /// What to capture: full display, window, or region.
    public var target: CaptureTarget
    /// Shape/position/size of the camera (PiP). Modifiable live.
    public var cameraLayout: CameraLayout
    /// AVCaptureDevice uniqueID; nil → default device.
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
