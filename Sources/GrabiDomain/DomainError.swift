import Foundation

/// Failures the domain itself can state, independent of any framework.
/// Presentation turns these into localized, actionable messages.
public enum GrabiError: Error, Equatable, Sendable {
    case noActiveSources
    case sourcesUnavailable([RecordingSource])
    case alreadyRecording
    case notRecording
    case engineFailure(String)
}
