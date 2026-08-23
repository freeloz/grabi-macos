import Foundation
import CoreGraphics
import GrabiDomain

/// Display names live where their strings live (this target's catalogs).
/// The domain types stay free of any localization.
public extension RecordingSource {
    var displayName: String {
        switch self {
        case .screen: return L("source.screen")
        case .camera: return L("source.camera")
        case .microphone: return L("source.microphone")
        case .systemAudio: return L("source.systemAudio")
        }
    }
}

public extension CameraShape {
    var displayName: String {
        switch self {
        case .circle: return L("shape.circle")
        case .square: return L("shape.square")
        case .rectangle: return L("shape.rectangle")
        }
    }
}

public extension AppLanguage {
    /// Its own name, or "same as my Mac" for the system option.
    var displayName: String { endonym ?? L("lang.system") }
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
