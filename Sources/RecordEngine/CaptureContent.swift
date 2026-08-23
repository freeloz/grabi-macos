import Foundation
import CoreGraphics
import ScreenCaptureKit
import GrabiDomain

/// Content available according to ScreenCaptureKit (requires screen permission).
public struct ShareableContent: Sendable {
    public let displays: [DisplayInfo]
    public let windows: [WindowInfo]

    // Cache of the raw SCK content from the last `current()`: the picker's
    // thumbnails reuse it to capture instantly without repeating the
    // SCShareableContent fetch (which takes ~1-2 s).
    private static let rawLock = NSLock()
    nonisolated(unsafe) private static var raw: SCShareableContent?

    public static func scWindow(for id: CGWindowID) -> SCWindow? {
        rawLock.lock(); defer { rawLock.unlock() }
        return raw?.windows.first { $0.windowID == id }
    }

    public static func scDisplay(for id: CGDirectDisplayID) -> SCDisplay? {
        rawLock.lock(); defer { rawLock.unlock() }
        return raw?.displays.first { $0.displayID == id }
    }

    private static func storeRaw(_ content: SCShareableContent) {
        rawLock.lock(); defer { rawLock.unlock() }
        raw = content
    }

    /// Lists capturable displays and windows. Excludes the app's own
    /// windows and untitled ones (menus, system overlays).
    public static func current() async throws -> ShareableContent {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw RecordingError.screenPermissionDenied
        }
        storeRaw(content)

        let mainID = CGMainDisplayID()
        let displays = content.displays.enumerated().map { index, display in
            DisplayInfo(
                id: display.displayID,
                name: display.displayID == mainID
                    ? L("display.builtin")
                    : String(format: L("display.numbered"), index + 1),
                frame: display.frame,
                isMain: display.displayID == mainID)
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // System overlays that show up as "windows" but make no sense
        // to record (Notification Center, Dock, Spotlight, etc.).
        let systemBundleIDs: Set<String> = [
            "com.apple.notificationcenterui",
            "com.apple.dock",
            "com.apple.controlcenter",
            "com.apple.WindowManager",
            "com.apple.Spotlight",
            "com.apple.systemuiserver",
            "com.apple.wallpaper.agent",
            "com.apple.screencaptureui",
        ]
        let windows = content.windows.compactMap { window -> WindowInfo? in
            guard let app = window.owningApplication,
                  app.processID != ownPID,
                  !systemBundleIDs.contains(app.bundleIdentifier),
                  window.isOnScreen,
                  window.windowLayer == 0, // only normal windows, no overlays/panels
                  window.frame.width >= 80, window.frame.height >= 60,
                  let title = window.title, !title.isEmpty
            else { return nil }
            return WindowInfo(id: window.windowID, appName: app.applicationName, title: title, frame: window.frame)
        }
        return ShareableContent(displays: displays, windows: windows)
    }
}
