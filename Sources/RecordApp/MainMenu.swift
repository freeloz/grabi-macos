import AppKit
import RecordUI

/// The app's menu bar (Phase 6). A menu-bar-only app has no menus of its
/// own; now that Grabi is a normal window app it needs them — not just for
/// discoverability, but because macOS routes ⌘C/⌘V/⌘W/⌘Q through here.
@MainActor
enum MainMenuBuilder {
    static func install(model: GrabiAppModel) {
        let main = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(item(L("menu.about"), #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        appMenu.addItem(.separator())
        appMenu.addItem(action(L("app.settings.checkUpdates")) { UpdaterManager.shared.checkForUpdates() })
        appMenu.addItem(.separator())
        appMenu.addItem(action(L("app.settings"), key: ",") { model.showMainWindow(tab: .settings) })
        appMenu.addItem(.separator())
        appMenu.addItem(item(L("menu.hide"), #selector(NSApplication.hide(_:)), key: "h"))
        let hideOthers = item(L("menu.hideOthers"), #selector(NSApplication.hideOtherApplications(_:)), key: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(item(L("menu.showAll"), #selector(NSApplication.unhideAllApplications(_:))))
        appMenu.addItem(.separator())
        appMenu.addItem(action(L("app.quit"), key: "q") { model.quit() })
        appItem.submenu = appMenu
        main.addItem(appItem)

        // File
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: L("menu.file"))
        let record = action(L("menu.newRecording"), key: "2", modifiers: [.command, .shift]) {
            model.toggleRecording()
        }
        fileMenu.addItem(record)
        fileMenu.addItem(action(L("menu.pause"), key: "p", modifiers: [.command, .shift]) {
            model.togglePause()
        })
        fileMenu.addItem(.separator())
        // El gesto más repetido del producto, a un atajo de distancia.
        fileMenu.addItem(action(L("menu.shareLast"), key: "s", modifiers: [.command, .shift]) {
            if let url = model.newestRecordingURL { model.shareToCloud(url: url) }
        })
        fileMenu.addItem(action(L("app.openFolder"), key: "o", modifiers: [.command, .shift]) {
            model.openRecordingsFolder()
        })
        fileMenu.addItem(.separator())
        fileMenu.addItem(item(L("menu.close"), #selector(NSWindow.performClose(_:)), key: "w"))
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        // Edit — standard responder selectors so text fields behave.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: L("menu.edit"))
        editMenu.addItem(item(L("menu.undo"), Selector(("undo:")), key: "z"))
        let redo = item(L("menu.redo"), Selector(("redo:")), key: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(item(L("menu.cut"), #selector(NSText.cut(_:)), key: "x"))
        editMenu.addItem(item(L("menu.copy"), #selector(NSText.copy(_:)), key: "c"))
        editMenu.addItem(item(L("menu.paste"), #selector(NSText.paste(_:)), key: "v"))
        editMenu.addItem(item(L("menu.selectAll"), #selector(NSText.selectAll(_:)), key: "a"))
        editItem.submenu = editMenu
        main.addItem(editItem)

        // Window
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: L("menu.window"))
        windowMenu.addItem(action(L("menu.mainWindow"), key: "0") { model.showMainWindow() })
        windowMenu.addItem(.separator())
        windowMenu.addItem(item(L("menu.minimize"), #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        windowMenu.addItem(item(L("menu.zoom"), #selector(NSWindow.performZoom(_:))))
        windowMenu.addItem(.separator())
        windowMenu.addItem(item(L("menu.front"), #selector(NSApplication.arrangeInFront(_:))))
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        // Help
        let helpItem = NSMenuItem()
        let helpMenu = NSMenu(title: L("menu.help"))
        helpMenu.addItem(action(L("menu.website")) { AppLinks.open(AppLinks.website) })
        helpMenu.addItem(action(L("app.settings.report")) { AppLinks.open(AppLinks.newIssue()) })
        helpItem.submenu = helpMenu
        main.addItem(helpItem)
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = main
    }

    // MARK: - Building blocks

    private static func item(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        NSMenuItem(title: title, action: selector, keyEquivalent: key)
    }

    /// Menu item backed by a closure (kept alive by the target object).
    private static func action(_ title: String,
                               key: String = "",
                               modifiers: NSEvent.ModifierFlags = [.command],
                               run: @escaping () -> Void) -> NSMenuItem {
        let target = ClosureTarget(run)
        let menuItem = NSMenuItem(title: title, action: #selector(ClosureTarget.fire), keyEquivalent: key)
        menuItem.keyEquivalentModifierMask = modifiers
        menuItem.target = target
        menuItem.representedObject = target // retains it
        return menuItem
    }
}

private final class ClosureTarget: NSObject {
    private let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire() { run() }
}
