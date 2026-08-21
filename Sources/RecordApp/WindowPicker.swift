import SwiftUI
import AppKit
import CoreGraphics
import ScreenCaptureKit
import RecordEngine
import RecordUI

/// Miniaturas para el selector visual.
///
/// En macOS 14+ usa SCScreenshotManager: captura por GPU directamente al
/// tamaño de la miniatura y en paralelo — carga casi instantánea. En macOS 13
/// cae a CGWindowListCreateImage/CGDisplayCreateImage (deprecadas en 14, pero
/// únicas disponibles ahí); son lentas porque el window server las atiende en
/// serie y a resolución completa.
actor CaptureThumbnailer {
    static let shared = CaptureThumbnailer()

    private var scWindows: [CGWindowID: SCWindow] = [:]
    private var scDisplays: [CGDirectDisplayID: SCDisplay] = [:]
    private var refreshed = false

    /// Ancho objetivo de las miniaturas en píxeles (tarjeta ~228 pt @2x).
    private let targetWidth: CGFloat = 480

    /// Un solo fetch de SCShareableContent por apertura del selector.
    func refresh() async {
        refreshed = false
        await ensureFresh()
    }

    private func ensureFresh() async {
        guard !refreshed else { return }
        refreshed = true
        guard #available(macOS 14.0, *) else { return }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return }
        scWindows = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })
        scDisplays = Dictionary(uniqueKeysWithValues: content.displays.map { ($0.displayID, $0) })
    }

    func window(_ windowID: CGWindowID) async -> NSImage? {
        await ensureFresh()
        if #available(macOS 14.0, *), let scWindow = scWindows[windowID] {
            let config = SCStreamConfiguration()
            let scale = min(1, targetWidth / max(scWindow.frame.width, 1))
            config.width = max(Int(scWindow.frame.width * scale), 2)
            config.height = max(Int(scWindow.frame.height * scale), 2)
            config.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            if let cgImage = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                return NSImage(cgImage: cgImage, size: .zero)
            }
        }
        return await Task.detached(priority: .userInitiated) {
            guard let cgImage = CGWindowListCreateImage(
                .null, .optionIncludingWindow, windowID,
                [.boundsIgnoreFraming, .nominalResolution])
            else { return nil }
            return NSImage(cgImage: cgImage, size: .zero)
        }.value
    }

    func display(_ displayID: CGDirectDisplayID) async -> NSImage? {
        await ensureFresh()
        if #available(macOS 14.0, *), let scDisplay = scDisplays[displayID] {
            let config = SCStreamConfiguration()
            let scale = targetWidth / max(CGFloat(scDisplay.width), 1)
            config.width = max(Int(CGFloat(scDisplay.width) * scale), 2)
            config.height = max(Int(CGFloat(scDisplay.height) * scale), 2)
            config.showsCursor = false
            let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
            if let cgImage = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                return NSImage(cgImage: cgImage, size: .zero)
            }
        }
        return await Task.detached(priority: .userInitiated) {
            guard let cgImage = CGDisplayCreateImage(displayID) else { return nil }
            return NSImage(cgImage: cgImage, size: .zero)
        }.value
    }
}

/// Selector visual de qué capturar (estilo Google Meet): miniaturas reales
/// de cada pantalla y cada ventana abierta; clic para elegir.
@MainActor
final class WindowPickerController: TitledWindowController {
    func show(model: GrabiAppModel) {
        present(title: L("app.picker.titulo"), size: NSSize(width: 720, height: 540),
                content: CapturePickerView(model: model, controller: self))
    }
}

private struct CapturePickerView: View {
    @ObservedObject var model: GrabiAppModel
    let controller: WindowPickerController

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 240), spacing: GrabiSpace.s4)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GrabiSpace.s6) {
                section(L("app.picker.pantallas")) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: GrabiSpace.s4) {
                        ForEach(model.availableDisplays) { display in
                            PickerCard(
                                title: display.name,
                                subtitle: "\(Int(display.frame.width))×\(Int(display.frame.height))",
                                isSelected: model.captureMode == .pantalla && isSelectedDisplay(display),
                                thumbnail: { await CaptureThumbnailer.shared.display(display.id) }
                            ) {
                                model.selectedDisplayID = display.isMain ? nil : display.id
                                model.captureMode = .pantalla
                                controller.close()
                            }
                        }
                    }
                }

                section(L("app.picker.ventanas")) {
                    if model.availableWindows.isEmpty {
                        HStack(spacing: GrabiSpace.s3) {
                            MascotView(pose: .neutral, size: 44)
                            Text(L("app.picker.vacio"))
                                .font(GrabiFont.body)
                                .foregroundStyle(GrabiColor.textSecondary)
                        }
                        .padding(.vertical, GrabiSpace.s4)
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: GrabiSpace.s4) {
                            ForEach(model.availableWindows) { window in
                                PickerCard(
                                    title: window.appName,
                                    subtitle: window.title,
                                    isSelected: model.captureMode == .ventana && model.selectedWindow?.id == window.id,
                                    thumbnail: { await CaptureThumbnailer.shared.window(window.id) }
                                ) {
                                    model.selectedWindow = window
                                    model.captureMode = .ventana
                                    controller.close()
                                }
                            }
                        }
                    }
                }
            }
            .padding(GrabiSpace.s6)
        }
        .frame(width: 720, height: 540)
        .background(GrabiColor.bg)
        .task {
            await CaptureThumbnailer.shared.refresh()
            await model.refreshAll()
        }
    }

    private func isSelectedDisplay(_ display: DisplayInfo) -> Bool {
        if let id = model.selectedDisplayID { return id == display.id }
        return display.isMain
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: GrabiSpace.s3) {
            Text(title)
                .font(GrabiFont.title3)
                .foregroundStyle(GrabiColor.text)
            content()
        }
    }
}

private struct PickerCard: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let thumbnail: () async -> NSImage?
    let action: () -> Void

    @State private var image: NSImage?
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: GrabiSpace.s2) {
                ZStack {
                    GrabiColor.track
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(6)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(height: 124)
                .clipShape(RoundedRectangle(cornerRadius: GrabiRadius.sm))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GrabiColor.text)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(GrabiColor.textSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
            .padding(8)
            .background(hovering ? GrabiColor.bg : GrabiColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: GrabiRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: GrabiRadius.md)
                    .strokeBorder(
                        isSelected ? GrabiColor.brandStrong : (hovering ? GrabiColor.borderStrong : GrabiColor.border),
                        lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(GrabiAnimation.standard(GrabiDuration.fast), value: hovering)
        .task { image = await thumbnail() }
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
