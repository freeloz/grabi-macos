import Foundation

/// Whether a source can be used, and why not when it can't.
public enum SourceStatus: Equatable, Sendable {
    case available
    case permissionDenied
    case unavailable(reason: String)

    public var isUsable: Bool { self == .available }
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
