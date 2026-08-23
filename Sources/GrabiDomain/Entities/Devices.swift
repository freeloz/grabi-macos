import Foundation

/// A camera or microphone the user can pick.
public struct CaptureDeviceInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    /// The one macOS would pick on its own.
    public let isSystemDefault: Bool

    public init(id: String, name: String, isSystemDefault: Bool) {
        self.id = id
        self.name = name
        self.isSystemDefault = isSystemDefault
    }
}

/// Which devices the user chose. `nil` means "whatever macOS picks", which
/// is also the fallback when a chosen device gets unplugged.
public struct DeviceSelection: Equatable, Sendable {
    public var cameraID: String?
    public var microphoneID: String?

    public init(cameraID: String? = nil, microphoneID: String? = nil) {
        self.cameraID = cameraID
        self.microphoneID = microphoneID
    }

    /// Drops ids that are no longer connected.
    public func reconciled(cameras: [CaptureDeviceInfo],
                           microphones: [CaptureDeviceInfo]) -> DeviceSelection {
        DeviceSelection(
            cameraID: cameras.contains { $0.id == cameraID } ? cameraID : nil,
            microphoneID: microphones.contains { $0.id == microphoneID } ? microphoneID : nil)
    }
}

/// The language Grabi speaks; `.system` follows the Mac.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, en, es, pt, fr, de
    public var id: String { rawValue }

    /// Written in its own language — how language pickers should read.
    /// `.system` has no self-name; presentation localizes that one.
    public var endonym: String? {
        switch self {
        case .system: return nil
        case .en: return "English"
        case .es: return "Español"
        case .pt: return "Português"
        case .fr: return "Français"
        case .de: return "Deutsch"
        }
    }
}
