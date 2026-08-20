import SwiftUI
import AppKit
import RecordUI

/// Grabi vive en la barra de menú (LSUIElement: sin ícono en el Dock).
@MainActor
enum AppShared {
    static let model = GrabiAppModel()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Primer arranque: onboarding de 3 pantallas que termina grabando.
        let model = AppShared.model
        if !model.onboardingDone {
            model.onboardingController.show(model: model)
        }
    }
}

@main
struct GrabiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = AppShared.model

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
