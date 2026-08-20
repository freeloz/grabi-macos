import SwiftUI
import RecordEngine
import RecordUI

/// Panel de barra de menú (Fase 3 §01): la prueba de los 5 segundos.
/// Qué se captura arriba, qué fuentes van dentro en medio, un solo botón
/// grande abajo. Ancho fijo 360.
struct PanelView: View {
    @ObservedObject var model: GrabiAppModel

    var body: some View {
        VStack(spacing: 14) {
            GrabiSegmented(items: [
                GrabiSegmentItem(CaptureMode.pantalla, label: "Pantalla", icon: .pantalla),
                GrabiSegmentItem(CaptureMode.ventana, label: "Ventana", icon: .ventana),
                GrabiSegmentItem(CaptureMode.region, label: "Región", icon: .region),
            ], selection: Binding(
                get: { model.captureMode },
                set: { newMode in
                    model.captureMode = newMode
                    if newMode == .region, model.regionRect == nil { model.pickRegion() }
                }
            ))
            .disabled(model.isActive)

            targetDetail

            SourceList {
                SourceRow(icon: .pantalla, title: "Pantalla", subtitle: model.captureLabel,
                          status: model.status(for: .screen),
                          isOn: Binding(get: { model.screenEnabled }, set: { model.screenEnabled = $0 }),
                          onPermissionTap: { model.openPermissionFlow(for: .screen) })
                    .disabled(model.isActive)
                RowDivider()
                SourceRow(icon: .forShape(model.cameraLayout.shape), title: "Cámara", subtitle: model.cameraSubtitle,
                          status: model.status(for: .camera),
                          isOn: Binding(get: { model.cameraEnabled }, set: { model.cameraEnabled = $0 }),
                          onPermissionTap: { model.openPermissionFlow(for: .camera) })
                    .disabled(model.isActive)
                RowDivider()
                SourceRow(icon: .microfono, title: "Micrófono", subtitle: model.micDeviceName,
                          status: model.status(for: .microphone),
                          isOn: Binding(get: { model.micEnabled }, set: { model.micEnabled = $0 }),
                          level: model.micLevel,
                          onPermissionTap: { model.openPermissionFlow(for: .microphone) })
                    .disabled(model.isActive)
                RowDivider()
                SourceRow(icon: .audioSistema, title: "Audio del sistema",
                          subtitle: model.systemAudioEnabled ? "Encendido" : "Apagado",
                          status: model.status(for: .systemAudio),
                          isOn: Binding(get: { model.systemAudioEnabled }, set: { model.systemAudioEnabled = $0 }),
                          level: model.systemLevel > 0 ? model.systemLevel : nil,
                          onPermissionTap: { model.openPermissionFlow(for: .systemAudio) })
                    .disabled(model.isActive)
            }

            RecordButton(
                state: recordButtonState,
                elapsed: model.elapsedText,
                height: 52,
                onRecord: { model.requestStart() },
                onPause: { model.togglePause() },
                onResume: { model.togglePause() },
                onStop: { Task { await model.stop() } })
                .disabled(!model.anySourceEnabled && !model.isActive)

            if let message = model.errorMessage {
                Text(message)
                    .font(GrabiFont.caption)
                    .foregroundStyle(GrabiColor.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            footer
        }
        .padding(16)
        .frame(width: 360)
        .background(GrabiColor.bg)
        .onAppear { model.panelAppeared() }
        .onDisappear { model.panelDisappeared() }
        .confirmationDialog(
            "Algunas fuentes no están disponibles",
            isPresented: $model.showUnavailableDialog,
            titleVisibility: .visible
        ) {
            Button("Grabar sin: \(model.unavailableSources.map(\.displayName).joined(separator: ", "))") {
                model.startWithoutUnavailable()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(model.unavailableSources
                .compactMap { model.preflight?.status(for: $0).explanation }
                .joined(separator: "\n\n"))
        }
    }

    private var recordButtonState: RecordButtonState {
        switch model.engineState {
        case .recording, .starting, .stopping: return .grabando
        case .paused: return .pausado
        default: return .listo
        }
    }

    /// Selector secundario según el modo: pantalla (si hay varias), ventana o región.
    @ViewBuilder
    private var targetDetail: some View {
        switch model.captureMode {
        case .pantalla:
            if model.availableDisplays.count > 1 {
                detailMenu(label: model.captureLabel) {
                    ForEach(model.availableDisplays) { display in
                        Button(display.name) {
                            model.selectedDisplayID = display.isMain ? nil : display.id
                        }
                    }
                }
            }
        case .ventana:
            detailMenu(label: model.captureLabel) {
                if model.availableWindows.isEmpty {
                    Button("No hay ventanas para capturar") {}.disabled(true)
                }
                ForEach(model.availableWindows) { window in
                    Button("\(window.appName) — \(String(window.title.prefix(40)))") {
                        model.selectedWindow = window
                    }
                }
            }
        case .region:
            HStack(spacing: GrabiSpace.s2) {
                Text(model.captureLabel)
                    .font(GrabiFont.caption)
                    .foregroundStyle(GrabiColor.textSecondary)
                Spacer()
                Button("Cambiar…") { model.pickRegion() }
                    .font(GrabiFont.caption)
                    .buttonStyle(.link)
                    .tint(GrabiColor.brandStrong)
            }
            .padding(.horizontal, 4)
        }
    }

    private func detailMenu(label: String, @ViewBuilder items: () -> some View) -> some View {
        Menu {
            items()
        } label: {
            HStack {
                Text(label)
                    .font(GrabiFont.caption)
                Spacer()
            }
        }
        .menuStyle(.borderlessButton)
        .disabled(model.isActive)
        .padding(.horizontal, 4)
    }

    private var footer: some View {
        HStack {
            Button("Vista previa en vivo") { model.openPreview() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(GrabiColor.brandStrong)
                .disabled(!model.screenEnabled && !model.cameraEnabled)
            Spacer()
            HStack(spacing: 14) {
                Button { model.openRecordingsFolder() } label: {
                    GrabiIconView(.carpeta, size: 16, tint: GrabiColor.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Abrir carpeta de grabaciones")
                Button { model.settingsController.show(model: model) } label: {
                    GrabiIconView(.ajustes, size: 16, tint: GrabiColor.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Ajustes")
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Etiqueta de la barra de menú: plantilla monocroma en reposo; punto de
/// color + cronómetro mientras se graba (honestidad: siempre visible).
struct MenuBarLabel: View {
    @ObservedObject var model: GrabiAppModel

    var body: some View {
        if model.isActive {
            HStack(spacing: 4) {
                Image(nsImage: MenuBarIcons.coloredDot(paused: model.isPaused))
                Text(model.elapsedText)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
            }
        } else {
            Image(nsImage: MenuBarIcons.templateRing)
        }
    }
}

enum MenuBarIcons {
    /// El punto con anillo, como plantilla del sistema.
    static let templateRing: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let ctx = NSGraphicsContext.current!.cgContext
            ctx.setStrokeColor(.black)
            ctx.setLineWidth(1.8)
            ctx.strokeEllipse(in: rect.insetBy(dx: 2.5, dy: 2.5))
            ctx.setFillColor(.black)
            ctx.fillEllipse(in: rect.insetBy(dx: 6.2, dy: 6.2))
            return true
        }
        image.isTemplate = true
        return image
    }()

    static func coloredDot(paused: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let ctx = NSGraphicsContext.current!.cgContext
            if paused {
                ctx.setFillColor(CGColor(red: 0xE4/255.0, green: 0xB4/255.0, blue: 0x5C/255.0, alpha: 1))
                let r = rect.insetBy(dx: 2.5, dy: 2.5)
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: 2.5, cornerHeight: 2.5, transform: nil))
                ctx.fillPath()
            } else {
                ctx.setFillColor(CGColor(red: 0xE5/255.0, green: 0x48/255.0, blue: 0x3F/255.0, alpha: 1))
                ctx.fillEllipse(in: rect.insetBy(dx: 2.5, dy: 2.5))
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
