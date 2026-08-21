import SwiftUI
import AppKit
import CoreGraphics
import ScreenCaptureKit
import RecordEngine
import RecordUI

/// Miniaturas del selector visual, con caché en memoria: reabrir el
/// selector muestra las miniaturas AL INSTANTE (las de la vez anterior) y
/// las refresca en paralelo por debajo.
///
/// Captura: en macOS 14+ SCScreenshotManager por GPU al tamaño exacto de la
/// tarjeta, reutilizando el SCShareableContent que el modelo ya trajo (cero
/// fetches extra). En macOS 13, CGWindowListCreateImage como fallback.
@MainActor
final class ThumbnailStore: ObservableObject {
    static let shared = ThumbnailStore()

    @Published private(set) var windowImages: [CGWindowID: NSImage] = [:]
    @Published private(set) var displayImages: [CGDirectDisplayID: NSImage] = [:]

    private let targetWidth: CGFloat = 480 // tarjeta ~228 pt @2x

    /// Captura todo en paralelo y actualiza el caché entrada a entrada
    /// (cada tarjeta se pinta en cuanto llega la suya).
    func refresh(displays: [DisplayInfo], windows: [WindowInfo]) async {
        await withTaskGroup(of: Void.self) { group in
            for display in displays {
                group.addTask { @MainActor [weak self] in
                    guard let self else { return }
                    if let image = await Self.captureDisplay(display.id, targetWidth: self.targetWidth) {
                        self.displayImages[display.id] = image
                    }
                }
            }
            for window in windows {
                group.addTask { @MainActor [weak self] in
                    guard let self else { return }
                    if let image = await Self.captureWindow(window.id, targetWidth: self.targetWidth) {
                        self.windowImages[window.id] = image
                    }
                }
            }
            await group.waitForAll()
        }
        // Purgar miniaturas de ventanas que ya no existen.
        let validWindows = Set(windows.map(\.id))
        windowImages = windowImages.filter { validWindows.contains($0.key) }
    }

    private nonisolated static func captureWindow(_ id: CGWindowID, targetWidth: CGFloat) async -> NSImage? {
        if #available(macOS 14.0, *), let scWindow = ShareableContent.scWindow(for: id) {
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
                .null, .optionIncludingWindow, id,
                [.boundsIgnoreFraming, .nominalResolution])
            else { return nil }
            return NSImage(cgImage: cgImage, size: .zero)
        }.value
    }

    private nonisolated static func captureDisplay(_ id: CGDirectDisplayID, targetWidth: CGFloat) async -> NSImage? {
        if #available(macOS 14.0, *), let scDisplay = ShareableContent.scDisplay(for: id) {
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
            guard let cgImage = CGDisplayCreateImage(id) else { return nil }
            return NSImage(cgImage: cgImage, size: .zero)
        }.value
    }
}

/// Selector visual de qué capturar (estilo Google Meet): miniaturas reales
/// de cada pantalla y cada ventana abierta; clic para elegir.
@MainActor
final class WindowPickerController: TitledWindowController {
    func show(model: GrabiAppModel) {
        present(title: L("app.picker.title"), size: NSSize(width: 720, height: 540),
                content: CapturePickerView(model: model, controller: self))
    }
}

private struct CapturePickerView: View {
    @ObservedObject var model: GrabiAppModel
    @ObservedObject private var thumbnails = ThumbnailStore.shared
    let controller: WindowPickerController

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 240), spacing: GrabiSpace.s4)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GrabiSpace.s6) {
                section(L("app.picker.displays")) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: GrabiSpace.s4) {
                        ForEach(model.availableDisplays) { display in
                            PickerCard(
                                title: display.name,
                                subtitle: "\(Int(display.frame.width))×\(Int(display.frame.height))",
                                isSelected: model.captureMode == .pantalla && isSelectedDisplay(display),
                                image: thumbnails.displayImages[display.id]
                            ) {
                                model.selectedDisplayID = display.isMain ? nil : display.id
                                model.captureMode = .pantalla
                                controller.close()
                            }
                        }
                    }
                }

                section(L("app.picker.windows")) {
                    if model.availableWindows.isEmpty {
                        HStack(spacing: GrabiSpace.s3) {
                            MascotView(pose: .neutral, size: 44)
                            Text(L("app.picker.empty"))
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
                                    image: thumbnails.windowImages[window.id]
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
            // 1. Pintar YA con lo conocido (caché de miniaturas + contenido
            //    SCK que el modelo ya trajo al abrir el panel).
            await thumbnails.refresh(displays: model.availableDisplays, windows: model.availableWindows)
            // 2. Refrescar la lista y volver a capturar lo nuevo.
            await model.refreshAll()
            await thumbnails.refresh(displays: model.availableDisplays, windows: model.availableWindows)
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
    let image: NSImage?
    let action: () -> Void

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
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
