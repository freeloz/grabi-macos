import SwiftUI
import AppKit
import RecordUI

/// Al lanzarse como ejecutable de Swift Package (fuera de un bundle normal),
/// hay que pedir explícitamente política de app regular para que la ventana
/// aparezca en primer plano con icono en el Dock.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct RecordApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Record", id: "main") {
            ContentView(model: model)
        }
        .windowResizability(.contentSize)

        // Galería del sistema de diseño (solo debug/verificación).
        Window("Galería Grabi", id: "gallery") {
            GrabiGallery()
        }
    }
}
