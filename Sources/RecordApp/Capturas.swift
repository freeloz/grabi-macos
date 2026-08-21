import SwiftUI
import AppKit
import RecordUI

/// Herramienta de verificación i18n (solo desarrollo): renderiza las
/// superficies principales a PNG en el idioma del proceso y termina.
///
///   .build/debug/RecordApp --capturas <dir> -AppleLanguages "(de)"
@MainActor
enum Capturas {
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

        save(PanelView(model: model).frame(width: 360), "panel")
        save(SettingsView(model: model, gallery: GalleryWindowController()).frame(width: 420, height: 470), "ajustes")
        save(OnboardingView(model: model, controller: OnboardingWindowController()), "onboarding")
    }
}
