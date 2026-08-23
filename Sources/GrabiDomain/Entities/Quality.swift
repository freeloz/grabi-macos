import Foundation

/// Recording quality. "Standard" shares light; "Sharp" keeps every pixel.
public enum RecordingQuality: String, CaseIterable, Identifiable, Sendable {
    case standard, sharp
    public var id: String { rawValue }

    /// Width the engine targets; the source's own size wins when smaller.
    public var targetWidth: Int {
        switch self {
        case .standard: return 1920
        case .sharp: return 3840
        }
    }

    /// Rough size on disk, for honest copy in the UI.
    public var gigabytesPerHour: Double {
        switch self {
        case .standard: return 3
        case .sharp: return 6
        }
    }
}

/// Framing costs should never equal recording costs: the preview runs small
/// and slow on purpose, so leaving the window open is cheap.
public enum PreviewBudget {
    public static let width = 1280
    public static let framesPerSecond = 10
    /// A PiP in a corner does not need 1080p; the camera-only mode does.
    public static func cameraHeight(pictureInPicture: Bool) -> Int {
        pictureInPicture ? 720 : 1080
    }
}
