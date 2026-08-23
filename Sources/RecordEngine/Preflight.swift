import Foundation
import AVFoundation
import CoreGraphics
import GrabiDomain

public enum Preflight {
    /// Checks availability and permissions of the 4 sources.
    ///
    /// If `requestingAccess` is true, asks the system for the permissions
    /// still in the "not determined" state (shows the macOS dialogs) —
    /// so the prompts appear before starting, never mid-recording.
    public static func check(requestingAccess: Bool = true) async -> PermissionReport {
        PermissionReport(
            screen: await screenStatus(requestingAccess: requestingAccess),
            camera: await cameraStatus(requestingAccess: requestingAccess),
            microphone: await microphoneStatus(requestingAccess: requestingAccess),
            systemAudio: await screenStatus(requestingAccess: false) // same permission as screen
        )
    }

    private static func screenStatus(requestingAccess: Bool) async -> SourceStatus {
        if CGPreflightScreenCaptureAccess() { return .available }
        if requestingAccess {
            // Only the first time does macOS show the prompt that leads to
            // System Settings; subsequent calls silently return false.
            if CGRequestScreenCaptureAccess() { return .available }
        }
        return .permissionDenied(help: RecordingError.screenPermissionDenied.errorDescription ?? "")
    }

    private static func cameraStatus(requestingAccess: Bool) async -> SourceStatus {
        guard AVCaptureDevice.default(for: .video) != nil else {
            return .unavailable(reason: RecordingError.cameraUnavailable.errorDescription ?? "")
        }
        return await mediaAuthStatus(for: .video, requestingAccess: requestingAccess,
                                     deniedHelp: RecordingError.cameraPermissionDenied.errorDescription ?? "")
    }

    private static func microphoneStatus(requestingAccess: Bool) async -> SourceStatus {
        guard AVCaptureDevice.default(for: .audio) != nil else {
            return .unavailable(reason: RecordingError.microphoneUnavailable.errorDescription ?? "")
        }
        return await mediaAuthStatus(for: .audio, requestingAccess: requestingAccess,
                                     deniedHelp: RecordingError.microphonePermissionDenied.errorDescription ?? "")
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
