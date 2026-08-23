import Foundation
import GrabiDomain

/// Engine errors: actionable and localized (the target's
/// Localizable.strings; the permission instructions use the REAL System
/// Settings paths in each language).
public enum RecordingError: LocalizedError, Equatable {
    case noActiveSources
    case screenPermissionDenied
    case cameraPermissionDenied
    case microphonePermissionDenied
    case cameraUnavailable
    case microphoneUnavailable
    case displayNotFound
    case windowNotFound
    case invalidRegion
    case captureInterrupted(String)
    case writeFailed(String)
    case nothingRecorded
    case invalidState(String)

    public var errorDescription: String? {
        switch self {
        case .noActiveSources: return L("err.noSources")
        case .screenPermissionDenied: return L("err.screenPermission")
        case .cameraPermissionDenied: return L("err.cameraPermission")
        case .microphonePermissionDenied: return L("err.micPermission")
        case .cameraUnavailable: return L("err.cameraUnavailable")
        case .microphoneUnavailable: return L("err.micUnavailable")
        case .displayNotFound: return L("err.displayNotFound")
        case .windowNotFound: return L("err.windowNotFound")
        case .invalidRegion: return L("err.invalidRegion")
        case .captureInterrupted(let detail): return String(format: L("err.captureInterrupted"), detail)
        case .writeFailed(let detail): return String(format: L("err.writeFailed"), detail)
        case .nothingRecorded: return L("err.nothingRecorded")
        case .invalidState(let detail): return String(format: L("err.invalidState"), detail)
        }
    }
}
