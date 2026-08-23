import Foundation
import CoreGraphics

/// What counts as "the screen": a whole display, one window, or a region.
public enum CaptureTarget: Equatable, Hashable, Sendable {
    case display(CGDirectDisplayID?)
    case window(CGWindowID)
    /// Region in points, top-left origin relative to the display.
    case region(displayID: CGDirectDisplayID?, rect: CGRect)

    public static let mainDisplay = CaptureTarget.display(nil)
}

/// How the user chose to frame the capture (drives the picker in the UI).
public enum CaptureMode: String, CaseIterable, Identifiable, Sendable {
    case screen, window, region
    public var id: String { rawValue }
}

public struct DisplayInfo: Identifiable, Equatable, Sendable {
    public let id: CGDirectDisplayID
    public let name: String
    public let frame: CGRect
    public let isMain: Bool

    public init(id: CGDirectDisplayID, name: String, frame: CGRect, isMain: Bool) {
        self.id = id
        self.name = name
        self.frame = frame
        self.isMain = isMain
    }
}

public struct WindowInfo: Identifiable, Equatable, Sendable {
    public let id: CGWindowID
    public let appName: String
    public let title: String
    public let frame: CGRect

    public init(id: CGWindowID, appName: String, title: String, frame: CGRect) {
        self.id = id
        self.appName = appName
        self.title = title
        self.frame = frame
    }
}

/// Displays and windows available to capture right now.
public struct ShareableContent: Equatable, Sendable {
    public let displays: [DisplayInfo]
    public let windows: [WindowInfo]

    public init(displays: [DisplayInfo], windows: [WindowInfo]) {
        self.displays = displays
        self.windows = windows
    }

    public static let empty = ShareableContent(displays: [], windows: [])
}
