import SwiftUI
import AppKit
import AVFoundation
import RecordEngine
import RecordUI

/// Ventana titulada simple reutilizable.
@MainActor
class TitledWindowController: NSObject, NSWindowDelegate {
    var window: NSWindow?

    func present<Content: View>(title: String, size: NSSize, content: Content) {
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            win.title = title
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.center()
            window = win
        }
        window?.contentView = NSHostingView(rootView: content)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
    }
}

// MARK: - Onboarding (Fase 3 §06): 3 pantallas y a grabar

@MainActor
final class OnboardingWindowController: TitledWindowController {
    func show(model: GrabiAppModel) {
        present(title: "", size: NSSize(width: 520, height: 460),
                content: OnboardingView(model: model, controller: self))
    }
}

struct OnboardingView: View {
    @ObservedObject var model: GrabiAppModel
    let controller: OnboardingWindowController
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(L("app.ob.skip")) { finish(startRecording: false) }
                    .buttonStyle(.plain)
                    .font(GrabiFont.caption)
                    .foregroundStyle(GrabiColor.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            Group {
                switch step {
                case 0: page0
                case 1: page1
                default: page2
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i == step ? GrabiColor.brandStrong : GrabiColor.border)
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.bottom, 24)
        }
        .frame(width: 520, height: 460)
        .background(GrabiColor.bg)
        .task { await model.refreshAll() }
    }

    private var page0: some View {
        VStack(spacing: 16) {
            MascotView(pose: .saludando, size: 116)
            Text(L("app.ob.hello"))
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(GrabiColor.text)
            Text(L("app.ob.claim"))
                .font(.system(size: 14.5))
                .foregroundStyle(GrabiColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Spacer().frame(height: 4)
            GrabiButton(L("app.ob.start"), kind: .primario) { step = 1 }
        }
        .padding(.horizontal, 36)
    }

    private var page1: some View {
        VStack(spacing: 14) {
            MascotView(pose: .neutral, size: 76)
            Text(L("app.ob.permissions.title"))
                .font(.system(size: 21, weight: .heavy))
                .foregroundStyle(GrabiColor.text)
            Text(L("app.ob.permissions.sub"))
                .font(.system(size: 13.5))
                .foregroundStyle(GrabiColor.textSecondary)
            VStack(spacing: 8) {
                permissionRow(
                    icon: .pantalla, title: RecordingSource.screen.displayName,
                    granted: model.preflight?.screen.isUsable == true,
                    action: { model.openScreenSettings() })
                permissionRow(
                    icon: .microfono, title: RecordingSource.microphone.displayName,
                    granted: model.preflight?.microphone.isUsable == true,
                    action: {
                        Task {
                            _ = await RecordingEngine.preflight(requestingAccess: true)
                            await model.refreshAll()
                        }
                    })
            }
            GrabiButton(L("app.ob.continue"), kind: .primario) { step = 2 }
            Button(L("app.ob.later")) { step = 2 }
                .buttonStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(GrabiColor.textSecondary)
        }
        .padding(.horizontal, 34)
    }

    private func permissionRow(icon: GrabiIcon, title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 11) {
            GrabiIconView(icon, size: 17, tint: granted ? GrabiColor.exito : GrabiColor.text)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GrabiColor.text)
            Spacer()
            if granted {
                Text(L("app.ob.granted"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GrabiColor.exito)
            } else {
                Button(action: action) {
                    Text(L("app.ob.allow"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GrabiColor.onBrand)
                        .padding(.horizontal, 13)
                        .frame(height: 28)
                        .background(GrabiColor.brandStrong)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(granted ? GrabiColor.exitoBg : GrabiColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(GrabiColor.border, lineWidth: 1))
    }

    private var page2: some View {
        VStack(spacing: 14) {
            MascotView(pose: .grabando, size: 86)
            Text(L("app.ob.first.title"))
                .font(.system(size: 21, weight: .heavy))
                .foregroundStyle(GrabiColor.text)
            Text(L("app.ob.first.sub"))
                .font(.system(size: 13.5))
                .foregroundStyle(GrabiColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 290)
            Spacer().frame(height: 4)
            Button { finish(startRecording: true) } label: {
                HStack(spacing: 10) {
                    SemaforoDot(.listo, size: 12)
                    Text(L("app.ob.testRecording"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GrabiColor.text)
                }
                .padding(.horizontal, 26)
                .frame(height: 48)
                .background(GrabiColor.surface)
                .overlay(Capsule().strokeBorder(GrabiColor.borderStrong, lineWidth: 1.5))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 34)
    }

    private func finish(startRecording: Bool) {
        model.onboardingDone = true
        controller.close()
        if startRecording {
            model.requestStart()
        }
    }
}

// MARK: - Flujo de permisos (Fase 3 §04): honestidad + pasos numerados

@MainActor
final class PermissionWindowController: TitledWindowController {
    func show(model: GrabiAppModel, source: RecordingSource) {
        // Cámara/mic sin determinar → diálogo del sistema directamente.
        if source == .camera || source == .microphone {
            let mediaType: AVMediaType = source == .camera ? .video : .audio
            if AVCaptureDevice.authorizationStatus(for: mediaType) == .notDetermined {
                Task {
                    _ = await AVCaptureDevice.requestAccess(for: mediaType)
                    await model.refreshAll()
                }
                return
            }
        }
        present(title: "", size: NSSize(width: 400, height: 300),
                content: PermissionView(model: model, controller: self, source: source))
    }
}

private struct PermissionView: View {
    @ObservedObject var model: GrabiAppModel
    let controller: PermissionWindowController
    let source: RecordingSource

    private var titleText: String {
        switch source {
        case .screen, .systemAudio: return L("app.perm.title.screen")
        case .camera: return L("app.perm.title.camera")
        case .microphone: return L("app.perm.title.microphone")
        }
    }

    private var settingsPane: String {
        switch source {
        case .screen, .systemAudio: return L("app.perm.panel.screen")
        case .camera: return L("app.perm.panel.camera")
        case .microphone: return L("app.perm.panel.microphone")
        }
    }

    private var settingsURL: URL {
        let anchor: String
        switch source {
        case .screen, .systemAudio: anchor = "Privacy_ScreenCapture"
        case .camera: anchor = "Privacy_Camera"
        case .microphone: anchor = "Privacy_Microphone"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                MascotView(pose: .preocupado, size: 60)
                VStack(alignment: .leading, spacing: 3) {
                    Text(titleText)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(GrabiColor.text)
                    Text(L("app.perm.honest"))
                        .font(GrabiFont.caption)
                        .foregroundStyle(GrabiColor.textSecondary)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                stepRow(1, text: L("app.perm.step1"))
                stepRow(2, text: LF("app.perm.step2", settingsPane))
                stepRow(3, text: L("app.perm.step3"))
            }
            HStack {
                Spacer()
                GrabiButton(L("app.perm.notNow"), kind: .fantasma) { controller.close() }
                GrabiButton(L("app.perm.openSettings"), kind: .primario) {
                    NSWorkspace.shared.open(settingsURL)
                }
            }
        }
        .padding(28)
        .frame(width: 400)
        .background(GrabiColor.bg)
    }

    private func stepRow(_ n: Int, text: String) -> some View {
        HStack(spacing: 12) {
            Text("\(n)")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(GrabiColor.bg)
                .frame(width: 24, height: 24)
                .background(Circle().fill(GrabiColor.text))
            Text(.init(text))
                .font(.system(size: 13.5))
                .foregroundStyle(GrabiColor.text)
        }
    }
}

// MARK: - Ajustes (mínimos: carpeta + atajos)

@MainActor
final class SettingsWindowController: TitledWindowController {
    private let gallery = GalleryWindowController()

    func show(model: GrabiAppModel) {
        present(title: L("app.settings.title"), size: NSSize(width: 420, height: 470),
                content: SettingsView(model: model, gallery: gallery))
    }
}

struct SettingsView: View {
    @ObservedObject var model: GrabiAppModel
    let gallery: GalleryWindowController

    var body: some View {
        VStack(alignment: .leading, spacing: GrabiSpace.s6) {
            VStack(alignment: .leading, spacing: GrabiSpace.s2) {
                Text(L("app.settings.folder"))
                    .font(GrabiFont.bodySemibold)
                    .foregroundStyle(GrabiColor.text)
                HStack {
                    GrabiIconView(.carpeta, size: 16, tint: GrabiColor.textSecondary)
                    Text(model.destinationFolder.path.replacingOccurrences(
                        of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                        .font(GrabiFont.caption)
                        .foregroundStyle(GrabiColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    GrabiButton(L("app.change"), kind: .secundario) { pickFolder() }
                }
                .padding(12)
                .background(GrabiColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(GrabiColor.border, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: GrabiSpace.s2) {
                Text(L("app.settings.quality"))
                    .font(GrabiFont.bodySemibold)
                    .foregroundStyle(GrabiColor.text)
                VStack(spacing: 0) {
                    qualityRow(.estandar)
                    RowDivider()
                    qualityRow(.nitida)
                }
                .background(GrabiColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(GrabiColor.border, lineWidth: 1))
                if model.isActive {
                    Text(L("app.settings.quality.note"))
                        .font(GrabiFont.caption)
                        .foregroundStyle(GrabiColor.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: GrabiSpace.s2) {
                Text(L("app.settings.shortcuts"))
                    .font(GrabiFont.bodySemibold)
                    .foregroundStyle(GrabiColor.text)
                VStack(spacing: 0) {
                    shortcutRow(L("app.settings.shortcut.record"), keys: "⌘⇧2")
                    RowDivider()
                    shortcutRow(L("app.settings.shortcut.pause"), keys: "⌘⇧P")
                }
                .background(GrabiColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(GrabiColor.border, lineWidth: 1))
            }

            Spacer()

            HStack {
                Button(L("app.settings.showOnboarding")) {
                    model.onboardingController.show(model: model)
                }
                .buttonStyle(.link)
                .font(GrabiFont.caption)
                Button(L("app.settings.gallery")) { gallery.show() }
                    .buttonStyle(.link)
                    .font(GrabiFont.caption)
                Spacer()
                GrabiButton(L("app.settings.quit"), kind: .fantasma) { model.quit() }
            }
        }
        .padding(20)
        .frame(width: 420, height: 470)
        .background(GrabiColor.bg)
    }

    /// Fila de calidad: toda la fila es clicable, check en brand-strong para
    /// la seleccionada (patrón del dropdown, Fase 2 §05).
    private func qualityRow(_ quality: RecordingQuality) -> some View {
        let selected = model.quality == quality
        return HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 2) {
                Text(quality.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GrabiColor.text)
                Text(quality.hint)
                    .font(.system(size: 11.5))
                    .foregroundStyle(GrabiColor.textSecondary)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(GrabiColor.brandStrong)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { model.quality = quality }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func shortcutRow(_ label: String, keys: String) -> some View {
        HStack {
            Text(label)
                .font(GrabiFont.body)
                .foregroundStyle(GrabiColor.text)
            Spacer()
            Text(keys)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(GrabiColor.textSecondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(GrabiColor.chip)
                .clipShape(RoundedRectangle(cornerRadius: GrabiRadius.xs))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("app.settings.choose")
        panel.directoryURL = model.destinationFolder
        if panel.runModal() == .OK, let url = panel.url {
            model.destinationFolder = url
        }
    }
}

// MARK: - Galería (debug)

@MainActor
final class GalleryWindowController: TitledWindowController {
    func show() {
        present(title: "Galería Grabi", size: NSSize(width: 880, height: 640), content: GrabiGallery())
    }
}
