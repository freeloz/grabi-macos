import Foundation
import CoreGraphics
import ScreenCaptureKit

/// Qué capturar como "pantalla": una pantalla completa, una ventana de otra
/// app, o una región rectangular de una pantalla.
public enum CaptureTarget: Equatable, Sendable {
    /// Pantalla completa. `nil` → pantalla principal.
    case display(CGDirectDisplayID?)
    /// Una ventana concreta (ID de CGWindow / SCWindow).
    case window(CGWindowID)
    /// Región de una pantalla. `rect` en puntos, con origen arriba-izquierda
    /// relativo a esa pantalla (el mismo sistema de coordenadas que
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

/// Pantalla disponible para capturar.
public struct DisplayInfo: Identifiable, Equatable, Sendable {
    public let id: CGDirectDisplayID
    /// "Pantalla integrada", "Pantalla 2", …
    public let name: String
    public let frame: CGRect
    public let isMain: Bool
}

/// Ventana disponible para capturar.
public struct WindowInfo: Identifiable, Equatable, Sendable {
    public let id: CGWindowID
    public let appName: String
    public let title: String
    public let frame: CGRect
}

/// Contenido disponible según ScreenCaptureKit (requiere permiso de pantalla).
public struct ShareableContent: Sendable {
    public let displays: [DisplayInfo]
    public let windows: [WindowInfo]

    /// Lista pantallas y ventanas capturables. Excluye las ventanas de la
    /// propia app y las que no tienen título (menús, overlays del sistema).
    public static func current() async throws -> ShareableContent {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw RecordingError.permisoPantallaDenegado
        }
        let mainID = CGMainDisplayID()
        let displays = content.displays.enumerated().map { index, display in
            DisplayInfo(
                id: display.displayID,
                name: display.displayID == mainID ? "Pantalla integrada" : "Pantalla \(index + 1)",
                frame: display.frame,
                isMain: display.displayID == mainID)
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windows = content.windows.compactMap { window -> WindowInfo? in
            guard let app = window.owningApplication,
                  app.processID != ownPID,
                  window.isOnScreen,
                  window.frame.width >= 80, window.frame.height >= 60,
                  let title = window.title, !title.isEmpty
            else { return nil }
            return WindowInfo(id: window.windowID, appName: app.applicationName, title: title, frame: window.frame)
        }
        return ShareableContent(displays: displays, windows: windows)
    }
}
