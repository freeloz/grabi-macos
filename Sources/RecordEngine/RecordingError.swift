import Foundation

/// Errores del motor: accionables y localizados (Localizable.strings del
/// target; las instrucciones de permisos usan las rutas REALES de Ajustes
/// del Sistema en cada idioma).
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
        case .captureInterrupted(let detalle): return String(format: L("err.captureInterrupted"), detalle)
        case .writeFailed(let detalle): return String(format: L("err.writeFailed"), detalle)
        case .nothingRecorded: return L("err.nothingRecorded")
        case .invalidState(let detalle): return String(format: L("err.invalidState"), detalle)
        }
    }
}
