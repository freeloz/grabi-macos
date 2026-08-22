import SwiftUI
import AppKit
import RecordUI

/// Grabi is a normal Mac app (Phase 6): Dock icon, its own menu bar and one
/// main window. The menu bar item stays as optional quick access.
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
        if let idx = CommandLine.arguments.firstIndex(of: "--window-shot"),
           CommandLine.arguments.count > idx + 1 {
            NSApp.setActivationPolicy(.regular)
            MainMenuBuilder.install(model: AppShared.model)
            Screenshots.captureWindow(to: CommandLine.arguments[idx + 1], model: AppShared.model)
            exit(0)
        }
        if CommandLine.arguments.contains("--idletest") {
            NSApp.setActivationPolicy(.regular)
            Screenshots.idleTest(model: AppShared.model)
            exit(0)
        }
        if CommandLine.arguments.contains("--selftest") {
            NSApp.setActivationPolicy(.regular)
            MainMenuBuilder.install(model: AppShared.model)
            Screenshots.selfTest(model: AppShared.model)
            exit(0)
        }
        NSApp.setActivationPolicy(.regular)
        // Start Sparkle now, not on first Settings open: the daily quiet
        // check must run even if the user never opens Settings.
        _ = UpdaterManager.shared
        let model = AppShared.model
        MainMenuBuilder.install(model: model)
        model.showMainWindow()
    }

    /// Closing the window doesn't quit: Grabi stays in the menu bar, and
    /// clicking the Dock icon brings the window back.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            Task { @MainActor in AppShared.model.showMainWindow() }
        }
        return true
    }
}

@main
struct GrabiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = AppShared.model
    /// Bound straight to UserDefaults on purpose: driving `isInserted` from a
    /// @Published property makes SwiftUI write back into the binding on every
    /// scene update, which pegs the main thread in a layout loop.
    @AppStorage("quickAccessEnabled") private var quickAccess = true

    var body: some Scene {
        MenuBarExtra(isInserted: $quickAccess) {
            PanelView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
