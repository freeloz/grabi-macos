import SwiftUI
import AppKit
import RecordUI

/// Grabi lives in the menu bar (LSUIElement: no Dock icon).
@MainActor
enum AppShared {
    static let model = GrabiAppModel()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // i18n verification: render surfaces to PNG and exit.
        if let idx = CommandLine.arguments.firstIndex(of: "--screenshots"),
           CommandLine.arguments.count > idx + 1 {
            Screenshots.renderAll(to: CommandLine.arguments[idx + 1], model: AppShared.model)
            exit(0)
        }
        NSApp.setActivationPolicy(.accessory)
        // Start Sparkle now, not on first Settings open: the daily quiet
        // check must run even if the user never opens Settings.
        _ = UpdaterManager.shared
        // First launch: 3-screen onboarding that ends by recording.
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
