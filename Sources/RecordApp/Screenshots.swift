import SwiftUI
import AppKit
import RecordUI

/// i18n verification tool (development only): renders the main surfaces
/// to PNG in the process language and exits.
///
///   .build/debug/RecordApp --screenshots <dir> -AppleLanguages "(de)"
@MainActor
enum Screenshots {
    /// End-to-end check of the record path (dev only): opens the window so
    /// the preview is running, records for a few seconds, stops, and reports
    /// the resulting file. Catches regressions in the preview→record
    /// pipeline rebuild.
    static func selfTest(model: GrabiAppModel) {
        model.showMainWindow()
        RunLoop.main.run(until: Date().addingTimeInterval(3))
        print("preview running, starting recording…")
        model.requestStart()
        RunLoop.main.run(until: Date().addingTimeInterval(12))
        Task { await model.stop() }
        RunLoop.main.run(until: Date().addingTimeInterval(4))
        if let url = model.lastRecordingURL {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            print("✓ recorded: \(url.lastPathComponent) — \(ByteCountFormatter.string(fromByteCount: size ?? 0, countStyle: .file))")
            print("✓ library items: \(model.library.items.count)")
        } else {
            print("✗ no recording produced — \(model.errorMessage ?? "no error reported")")
        }
    }

    /// Captures the REAL main window (AppKit render) — what ImageRenderer
    /// cannot show: NSViews, switches and lazy grids. Dev only.
    static func captureWindow(to dir: String, model: GrabiAppModel) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let wasDone = model.onboardingDone
        model.onboardingDone = true
        for tab in MainTab.allCases {
            model.showMainWindow(tab: tab)
            RunLoop.main.run(until: Date().addingTimeInterval(2.0))
            guard let view = model.mainWindow.window?.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("window-\(tab.rawValue).png"))
                print("✓ window-\(tab.rawValue).png")
            }
        }
        // First run, inside the window.
        model.onboardingDone = false
        model.showMainWindow(tab: .record)
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        if let view = model.mainWindow.window?.contentView,
           let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("window-welcome.png"))
                print("✓ window-welcome.png")
            }
        }
        model.onboardingDone = wasDone
    }

    static func renderAll(to dir: String, model: GrabiAppModel) {
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let lang = Locale.preferredLanguages.first?.prefix(2) ?? "xx"

        func save(_ view: some View, _ name: String) {
            let renderer = ImageRenderer(content: view.background(GrabiColor.bg))
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:])
            else { print("✗ \(name)-\(lang)"); return }
            try? png.write(to: url.appendingPathComponent("\(name)-\(lang).png"))
            print("✓ \(name)-\(lang).png")
        }

        // Main window (Phase 6): record + library, without touching the
        // user's real onboarding state.
        let wasDone = model.onboardingDone
        model.onboardingDone = true
        let recordController = MainWindowController()
        save(MainWindowRoot(model: model, controller: recordController).frame(width: 980, height: 660), "main-record")
        let libraryController = MainWindowController()
        libraryController.tab = .library
        save(MainWindowRoot(model: model, controller: libraryController).frame(width: 980, height: 660), "main-library")
        let settingsController = MainWindowController()
        settingsController.tab = .settings
        save(MainWindowRoot(model: model, controller: settingsController).frame(width: 980, height: 660), "main-settings")
        model.onboardingDone = false
        save(MainWindowRoot(model: model, controller: MainWindowController()).frame(width: 980, height: 660), "main-welcome")
        model.onboardingDone = wasDone

        save(PanelView(model: model).frame(width: 360), "panel")
        save(SettingsView(model: model, gallery: GalleryWindowController()).frame(width: 420, height: 580), "settings")
        save(OnboardingView(model: model, onFinish: { _ in }).frame(width: 520, height: 460), "onboarding")
    }
}
