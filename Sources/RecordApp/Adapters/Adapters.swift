import Foundation
import AppKit
import AVFoundation
import GrabiDomain
import RecordEngine

// The composition seam: every port gets an adapter that reuses the code the
// app already had. Swapping ScreenCaptureKit, the file system or the
// notification center means writing one of these — not touching a use case.

/// Preferences on UserDefaults.
final class UserDefaultsPreferences: PreferencesPort, @unchecked Sendable {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var destinationFolder: URL {
        get {
            if let path = defaults.string(forKey: "destinationFolder") {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Movies/Grabi", isDirectory: true)
        }
        set { defaults.set(newValue.path, forKey: "destinationFolder") }
    }

    var quality: RecordingQuality {
        get { RecordingQuality(rawValue: defaults.string(forKey: "recordingQuality") ?? "") ?? .standard }
        set { defaults.set(newValue.rawValue, forKey: "recordingQuality") }
    }

    var cameraLayout: CameraLayout {
        get {
            guard defaults.object(forKey: "camLayout.h") != nil,
                  let shape = CameraShape(rawValue: defaults.string(forKey: "camLayout.shape") ?? "")
            else { return .default }
            return CameraLayout(shape: shape,
                                origin: CGPoint(x: defaults.double(forKey: "camLayout.x"),
                                                y: defaults.double(forKey: "camLayout.y")),
                                height: defaults.double(forKey: "camLayout.h"))
        }
        set {
            defaults.set(newValue.shape.rawValue, forKey: "camLayout.shape")
            defaults.set(newValue.origin.x, forKey: "camLayout.x")
            defaults.set(newValue.origin.y, forKey: "camLayout.y")
            defaults.set(newValue.height, forKey: "camLayout.h")
        }
    }

    var devices: DeviceSelection {
        get { DeviceSelection(cameraID: defaults.string(forKey: "cameraDeviceID"),
                              microphoneID: defaults.string(forKey: "microphoneDeviceID")) }
        set {
            defaults.set(newValue.cameraID, forKey: "cameraDeviceID")
            defaults.set(newValue.microphoneID, forKey: "microphoneDeviceID")
        }
    }

    var language: AppLanguage {
        get { AppLanguage(rawValue: defaults.string(forKey: "appLanguage") ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: "appLanguage") }
    }

    var quickAccessEnabled: Bool {
        get { defaults.object(forKey: "quickAccessEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "quickAccessEnabled") }
    }

    var onboardingDone: Bool {
        get { defaults.bool(forKey: "onboardingDone") }
        set { defaults.set(newValue, forKey: "onboardingDone") }
    }
}

/// Cameras and microphones through AVFoundation.
struct AVDeviceDirectory: DeviceDirectoryPort {
    func cameras() -> [CaptureDeviceInfo] { CaptureDevices.cameras() }
    func microphones() -> [CaptureDeviceInfo] { CaptureDevices.microphones() }
}

/// The language switch, applied to the running app.
struct RuntimeLocalization: LocalizationPort {
    func apply(_ language: AppLanguage) { GrabiLocale.set(language) }
}

/// The recordings folder, read straight from disk.
struct FileSystemLibrary: RecordingLibraryPort {
    func recordings(in folder: URL) -> [Recording] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles])) ?? []
        return urls.filter { $0.pathExtension.lowercased() == "mov" }.map { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return Recording(id: url,
                             name: url.deletingPathExtension().lastPathComponent,
                             date: values?.contentModificationDate ?? .distantPast,
                             sizeBytes: Int64(values?.fileSize ?? 0))
        }
    }

    func duration(of recording: Recording) async -> TimeInterval? {
        try? await AVURLAsset(url: recording.id).load(.duration).seconds
    }

    func moveToTrash(_ recording: Recording) throws {
        try FileManager.default.trashItem(at: recording.id, resultingItemURL: nil)
    }

    func reveal(_ recording: Recording) {
        NSWorkspace.shared.activateFileViewerSelecting([recording.id])
    }

    func play(_ recording: Recording) {
        NSWorkspace.shared.open(recording.id)
    }

    /// Copies the file itself: ready to paste into Messages or Slack.
    func copyToPasteboard(_ recording: Recording) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([recording.id as NSURL])
    }
}
