import Foundation
import GrabiDomain

/// Lists the devices and keeps the stored choice honest: a webcam that was
/// unplugged silently falls back to the system default instead of failing
/// when the user hits record.
public struct RefreshDevicesUseCase: Sendable {
    private let directory: DeviceDirectoryPort

    public init(directory: DeviceDirectoryPort) { self.directory = directory }

    public struct Result: Equatable, Sendable {
        public let cameras: [CaptureDeviceInfo]
        public let microphones: [CaptureDeviceInfo]
        public let selection: DeviceSelection
        public var cameraChanged: Bool
        public var microphoneChanged: Bool
    }

    public func callAsFunction(current: DeviceSelection) -> Result {
        let cameras = directory.cameras()
        let microphones = directory.microphones()
        let reconciled = current.reconciled(cameras: cameras, microphones: microphones)
        return Result(cameras: cameras,
                      microphones: microphones,
                      selection: reconciled,
                      cameraChanged: reconciled.cameraID != current.cameraID,
                      microphoneChanged: reconciled.microphoneID != current.microphoneID)
    }
}

/// Switches the app's language and remembers it.
public struct ChangeLanguageUseCase: Sendable {
    private let localization: LocalizationPort
    private let preferences: PreferencesPort

    public init(localization: LocalizationPort, preferences: PreferencesPort) {
        self.localization = localization
        self.preferences = preferences
    }

    public func callAsFunction(_ language: AppLanguage) {
        preferences.language = language
        localization.apply(language)
    }
}
