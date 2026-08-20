import SwiftUI
import AppKit
import CoreGraphics
import RecordEngine
import RecordUI

/// Miniaturas para el selector visual. CGWindowListCreateImage /
/// CGDisplayCreateImage están deprecadas desde macOS 14 pero son la única
/// vía en macOS 13 (nuestro mínimo); con el permiso de pantalla concedido
/// devuelven el contenido real.
enum CaptureThumbnailer {
    static func window(_ windowID: CGWindowID) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            guard let cgImage = CGWindowListCreateImage(
                .null, .optionIncludingWindow, windowID,
                [.boundsIgnoreFraming, .nominalResolution])
            else { return nil }
            return NSImage(cgImage: cgImage, size: .zero)
        }.value
    }

    static func display(_ displayID: CGDirectDisplayID) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
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
        present(title: "Elegir qué capturar", size: NSSize(width: 720, height: 540),
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
                section("Pantallas") {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: GrabiSpace.s4) {
                        ForEach(model.availableDisplays) { display in
                            PickerCard(
                                title: display.name,
                                subtitle: "\(Int(display.frame.width))×\(Int(display.frame.height))",
                                isSelected: model.captureMode == .pantalla && isSelectedDisplay(display),
                                thumbnail: { await CaptureThumbnailer.display(display.id) }
                            ) {
                                model.selectedDisplayID = display.isMain ? nil : display.id
                                model.captureMode = .pantalla
                                controller.close()
                            }
                        }
                    }
                }

                section("Ventanas") {
                    if model.availableWindows.isEmpty {
                        HStack(spacing: GrabiSpace.s3) {
                            MascotView(pose: .neutral, size: 44)
                            Text("No hay ventanas para capturar. Abre la app que quieras grabar y vuelve aquí.")
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
                                    thumbnail: { await CaptureThumbnailer.window(window.id) }
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
        .task { await model.refreshAll() }
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
