import Foundation

/// Whether a source can be used, and why not when it can't.
public enum SourceStatus: Equatable, Sendable {
    case available
    /// Denied by macOS. `help` is the already-localized way out, supplied by
    /// the adapter thatknows the real System Settings pane.
    case permissionDenied(help: String)
    case unavailable(reason: String)

    public var isUsable: Bool {
        if case .available = self { return true }
        return false
    }

    /// What to tell the user when the source cannot be used.
    public var explanation: String? {
        switch self {
        case .available: return nil
        case .permissionDenied(let help): return help
        case .unavailable(let reason): return reason
        }
    }
}

/// Status of every source at a point in time.
public struct PermissionReport: Equatable, Sendable {
    public let screen: SourceStatus
    public let camera: SourceStatus
    public let microphone: SourceStatus
    public let systemAudio: SourceStatus

    public init(screen: SourceStatus, camera: SourceStatus,
                microphone: SourceStatus, systemAudio: SourceStatus) {
        self.screen = screen
        self.camera = camera
        self.microphone = microphone
        self.systemAudio = systemAudio
    }

    public func status(for source: RecordingSource) -> SourceStatus {
        switch source {
        case .screen: return screen
        case .camera: return camera
        case .microphone: return microphone
        case .systemAudio: return systemAudio
        }
    }

    /// Sources the user asked for that cannot actually record.
    public func blocked(in selection: SourceSelection) -> [RecordingSource] {
        selection.active.filter { !status(for: $0).isUsable }
    }

    public static let allAvailable = PermissionReport(
        screen: .available, camera: .available, microphone: .available, systemAudio: .available)
}
