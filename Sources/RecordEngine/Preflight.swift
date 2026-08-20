import Foundation
import AVFoundation
import CoreGraphics

/// Estado de una fuente según el chequeo previo.
public enum SourceStatus: Equatable, Sendable {
    case available
    case permissionDenied(help: String)
    case unavailable(reason: String)

    public var isUsable: Bool {
        if case .available = self { return true }
        return false
    }

    /// Texto en español para mostrar al usuario cuando la fuente no es usable.
    public var explanation: String? {
        switch self {
        case .available: return nil
        case .permissionDenied(let help): return help
        case .unavailable(let reason): return reason
        }
    }
}

/// Resultado del chequeo previo de las 4 fuentes. La UI lo usa para avisar
/// al usuario ANTES de iniciar y ofrecerle grabar sin las fuentes que fallen.
public struct PreflightReport: Equatable, Sendable {
    public let screen: SourceStatus
    public let camera: SourceStatus
    public let microphone: SourceStatus
    public let systemAudio: SourceStatus

    public func status(for source: RecordingSource) -> SourceStatus {
        switch source {
        case .screen: return screen
        case .camera: return camera
        case .microphone: return microphone
        case .systemAudio: return systemAudio
        }
    }
}

public enum Preflight {
    /// Chequea disponibilidad y permisos de las 4 fuentes.
    ///
    /// Si `requestingAccess` es true, solicita al sistema los permisos que
    /// estén en estado "no determinado" (muestra los diálogos de macOS) —
    /// así los avisos aparecen antes de iniciar, nunca a mitad de grabación.
    public static func check(requestingAccess: Bool = true) async -> PreflightReport {
        PreflightReport(
            screen: await screenStatus(requestingAccess: requestingAccess),
            camera: await cameraStatus(requestingAccess: requestingAccess),
            microphone: await microphoneStatus(requestingAccess: requestingAccess),
            systemAudio: await screenStatus(requestingAccess: false) // mismo permiso que pantalla
        )
    }

    private static func screenStatus(requestingAccess: Bool) async -> SourceStatus {
        if CGPreflightScreenCaptureAccess() { return .available }
        if requestingAccess {
            // Solo la primera vez macOS muestra el aviso que lleva a Ajustes;
            // las siguientes devuelve false en silencio.
            if CGRequestScreenCaptureAccess() { return .available }
        }
        return .permissionDenied(help: RecordingError.permisoPantallaDenegado.errorDescription ?? "")
    }

    private static func cameraStatus(requestingAccess: Bool) async -> SourceStatus {
        guard AVCaptureDevice.default(for: .video) != nil else {
            return .unavailable(reason: RecordingError.camaraNoDisponible.errorDescription ?? "")
        }
        return await mediaAuthStatus(for: .video, requestingAccess: requestingAccess,
                                     deniedHelp: RecordingError.permisoCamaraDenegado.errorDescription ?? "")
    }

    private static func microphoneStatus(requestingAccess: Bool) async -> SourceStatus {
        guard AVCaptureDevice.default(for: .audio) != nil else {
            return .unavailable(reason: RecordingError.microfonoNoDisponible.errorDescription ?? "")
        }
        return await mediaAuthStatus(for: .audio, requestingAccess: requestingAccess,
                                     deniedHelp: RecordingError.permisoMicrofonoDenegado.errorDescription ?? "")
    }

    private static func mediaAuthStatus(for mediaType: AVMediaType, requestingAccess: Bool, deniedHelp: String) async -> SourceStatus {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return .available
        case .notDetermined:
            guard requestingAccess else { return .permissionDenied(help: deniedHelp) }
            let granted = await AVCaptureDevice.requestAccess(for: mediaType)
            return granted ? .available : .permissionDenied(help: deniedHelp)
        default:
            return .permissionDenied(help: deniedHelp)
        }
    }
}
