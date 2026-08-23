import Foundation
import CoreGraphics

/// What Grabi can record. Each one is an independent toggle; the only rule
/// is that at least one has to be on.
public enum RecordingSource: String, CaseIterable, Identifiable, Sendable {
    case screen, camera, microphone, systemAudio
    public var id: String { rawValue }
}

/// Which set of sources the user picked.
public struct SourceSelection: Equatable, Sendable {
    public var screen: Bool
    public var camera: Bool
    public var microphone: Bool
    public var systemAudio: Bool

    public init(screen: Bool = true, camera: Bool = true,
                microphone: Bool = true, systemAudio: Bool = true) {
        self.screen = screen
        self.camera = camera
        self.microphone = microphone
        self.systemAudio = systemAudio
    }

    public subscript(source: RecordingSource) -> Bool {
        get {
            switch source {
            case .screen: return screen
            case .camera: return camera
            case .microphone: return microphone
            case .systemAudio: return systemAudio
            }
        }
        set {
            switch source {
            case .screen: screen = newValue
            case .camera: camera = newValue
            case .microphone: microphone = newValue
            case .systemAudio: systemAudio = newValue
            }
        }
    }

    public var isEmpty: Bool { !(screen || camera || microphone || systemAudio) }
    public var active: [RecordingSource] { RecordingSource.allCases.filter { self[$0] } }
    /// A preview can only show what has picture.
    public var hasVideo: Bool { screen || camera }
}

/// Shape of the camera over the video (design system: circle, square, or
/// 3:2 rectangle).
public enum CameraShape: String, CaseIterable, Identifiable, Sendable {
    case circle, square, rectangle
    public var id: String { rawValue }
    /// Width/height ratio (from the prototype: rect = 1.5 × height).
    public var aspectRatio: CGFloat { self == .rectangle ? 1.5 : 1.0 }
    /// Corner radius relative to the height (prototype: radius 12 at s=130).
    public var cornerRadiusFraction: CGFloat { self == .circle ? 0.5 : 12.0 / 130.0 }
}

/// Position, size and shape of the camera over the canvas, normalized (0–1)
/// so the same values describe the live preview and the recorded video.
/// Editable while recording.
public struct CameraLayout: Equatable, Sendable {
    public var shape: CameraShape
    /// Top-left corner, normalized over the canvas.
    public var origin: CGPoint
    /// Height normalized over the canvas height; width follows the shape.
    public var height: CGFloat

    /// From the approved prototype: circle, bottom right.
    public static let `default` = CameraLayout(
        shape: .circle,
        origin: CGPoint(x: 486.0 / 640.0, y: 206.0 / 360.0),
        height: 130.0 / 360.0)

    public init(shape: CameraShape, origin: CGPoint, height: CGFloat) {
        self.shape = shape
        self.origin = origin
        self.height = height
    }

    public var cornerRadiusFraction: CGFloat { shape.cornerRadiusFraction }

    /// Keeps the frame fully inside the canvas for a given canvas aspect.
    public func clamped(canvasWidth: CGFloat, canvasHeight: CGFloat) -> CameraLayout {
        guard canvasWidth > 0, canvasHeight > 0 else { return self }
        let widthFraction = height * shape.aspectRatio * (canvasHeight / canvasWidth)
        var copy = self
        copy.origin.x = min(max(origin.x, 0), max(0, 1 - widthFraction))
        copy.origin.y = min(max(origin.y, 0), max(0, 1 - height))
        return copy
    }
}
