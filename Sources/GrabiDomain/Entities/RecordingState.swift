import Foundation

/// Where a recording is in its life.
public enum RecordingState: Equatable, Sendable {
    case idle
    case starting
    case recording
    case paused
    case stopping
    case stopped(URL)
    case failed(String)

    /// Owns the devices: nothing else may release them.
    public var isActive: Bool {
        switch self {
        case .starting, .recording, .paused, .stopping: return true
        default: return false
        }
    }

    public var isRecording: Bool { self == .recording }
    public var isPaused: Bool { self == .paused }
}

/// A recording that exists on disk.
public struct Recording: Identifiable, Equatable, Sendable {
    /// The file is the identity.
    public let id: URL
    public let name: String
    public let date: Date
    public let sizeBytes: Int64
    public var duration: TimeInterval?

    public init(id: URL, name: String, date: Date, sizeBytes: Int64, duration: TimeInterval? = nil) {
        self.id = id
        self.name = name
        self.date = date
        self.sizeBytes = sizeBytes
        self.duration = duration
    }
}
