import Foundation
import CoreGraphics
import ScreenCaptureKit

/// What to capture as the "screen": a full display, a window of another
/// app, or a rectangular region of a display.
public enum CaptureTarget: Equatable, Sendable {
    /// Full display. `nil` → main display.
    case display(CGDirectDisplayID?)
    /// A specific window (CGWindow / SCWindow ID).
    case window(CGWindowID)
    /// Region of a display. `rect` in points, with a top-left origin
    /// relative to that display (the same coordinate system as
    /// `SCStreamConfiguration.sourceRect`).
    case region(displayID: CGDirectDisplayID?, rect: CGRect)

    public static let mainDisplay = CaptureTarget.display(nil)
}

extension CaptureTarget: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .display(let id):
            hasher.combine(0); hasher.combine(id)
        case .window(let id):
            hasher.combine(1); hasher.combine(id)
        case .region(let id, let rect):
            hasher.combine(2); hasher.combine(id)
            hasher.combine(rect.origin.x); hasher.combine(rect.origin.y)
            hasher.combine(rect.width); hasher.combine(rect.height)
        }
    }
}

/// Display available for capture.
public struct DisplayInfo: Identifiable, Equatable, Sendable {
    public let id: CGDirectDisplayID
    /// "Built-in Display", "Display 2", …
    public let name: String
    public let frame: CGRect
    public let isMain: Bool
}

/// Window available for capture.
public struct WindowInfo: Identifiable, Equatable, Sendable {
    public let id: CGWindowID
    public let appName: String
    public let title: String
    public let frame: CGRect
}

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
