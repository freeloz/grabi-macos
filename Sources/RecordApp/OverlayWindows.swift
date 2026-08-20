import SwiftUI
import AppKit
import RecordEngine
import RecordUI

/// Panel flotante no activante: base para pastilla y overlays.
private func makeFloatingPanel(level: NSWindow.Level) -> NSPanel {
    let panel = NSPanel(
        contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered, defer: false)
    panel.level = level
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    return panel
}

// MARK: - Pastilla flotante (Fase 3 §03)

/// Aparece al grabar, arrastrable, siempre encima y EXCLUIDA de la captura
/// (el motor excluye las ventanas de la propia app).
@MainActor
final class PillWindowController {
    private var panel: NSPanel?

    func show(model: GrabiAppModel) {
        if panel == nil {
            let p = makeFloatingPanel(level: .statusBar)
            p.isMovableByWindowBackground = true
            p.contentView = NSHostingView(rootView: PillRoot(model: model))
            panel = p
        }
        guard let panel else { return }
        panel.setContentSize(NSSize(width: 320, height: 56))
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - 160, y: f.maxY - 66))
        }
        panel.orderFrontRegardless()
    }

    func close() {
        panel?.orderOut(nil)
    }
}

private struct PillRoot: View {
    @ObservedObject var model: GrabiAppModel
    @State private var collapsed = false

    var body: some View {
        if model.isActive {
            FloatingPill(
                isPaused: model.isPaused,
                elapsed: model.elapsedText,
                collapsed: $collapsed,
                onPause: { model.togglePause() },
                onResume: { model.togglePause() },
                onStop: { Task { await model.stop() } })
                .padding(6)
                .fixedSize()
        }
    }
}

// MARK: - Cuenta regresiva 3·2·1 (Fase 3/4: mascota concentrándose)

@MainActor
final class CountdownWindowController {
    private var panel: NSPanel?

    func show(model: GrabiAppModel) {
        if panel == nil {
            let p = makeFloatingPanel(level: .screenSaver)
            p.contentView = NSHostingView(rootView: CountdownView(model: model))
            panel = p
        }
        guard let panel, let screen = NSScreen.main else { return }
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
    }

    func close() {
        panel?.orderOut(nil)
    }
}

private struct CountdownView: View {
    @ObservedObject var model: GrabiAppModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
            VStack(spacing: 18) {
                MascotView(pose: .grabando, size: 120)
                Text("\(model.countdown ?? 0)")
                    .font(.system(size: 88, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(nsColor: NSColor(srgbRed: 0xFA/255.0, green: 0xF7/255.0, blue: 0xF1/255.0, alpha: 1)))
                    .monospacedDigit()
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Selector de región (Fase C §3): overlay para dibujar el recuadro

@MainActor
final class RegionPickerController: NSObject {
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private weak var model: GrabiAppModel?

    func show(model: GrabiAppModel) {
        self.model = model
        guard let screen = NSScreen.main else { return }
        if panel == nil {
            let p = makeFloatingPanel(level: .screenSaver)
            p.contentView = NSHostingView(rootView: RegionPickView(
                onDone: { [weak self] rect in self?.finish(rect: rect) },
                onCancel: { [weak self] in self?.finish(rect: nil) }))
            panel = p
        }
        panel?.setFrame(screen.frame, display: true)
        panel?.orderFrontRegardless()
        // Esc cancela.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.finish(rect: nil); return nil }
            return event
        }
    }

    private func finish(rect: CGRect?) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.orderOut(nil)
        guard let model else { return }
        if let rect {
            model.regionRect = rect
            model.captureMode = .region
        } else if model.regionRect == nil, model.captureMode == .region {
            model.captureMode = .pantalla
        }
    }
}

/// Dibuja el recuadro con arrastre; coordenadas locales (arriba-izquierda)
/// == coordenadas de `sourceRect` porque la ventana cubre la pantalla entera.
private struct RegionPickView: View {
    let onDone: (CGRect) -> Void
    let onCancel: () -> Void

    @State private var start: CGPoint?
    @State private var current: CGPoint?

    private var rect: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(current.x - start.x), height: abs(current.y - start.y))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Velo con recorte en la región elegida.
                Canvas { context, size in
                    var veil = Path(CGRect(origin: .zero, size: size))
                    if let rect { veil.addRect(rect) }
                    context.fill(veil, with: .color(.black.opacity(0.35)), style: FillStyle(eoFill: true))
                    if let rect {
                        context.stroke(Path(rect), with: .color(GrabiColor.brandStrong), lineWidth: 2)
                    }
                }
                if let rect, rect.width > 40 {
                    Text("\(Int(rect.width)) × \(Int(rect.height))")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.7)))
                        .offset(x: rect.minX, y: max(rect.minY - 28, 4))
                }
                if start == nil {
                    VStack(spacing: 10) {
                        MascotView(pose: .neutral, size: 56)
                        Text("Dibuja la región que quieres grabar")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("esc para cancelar")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        if start == nil { start = value.startLocation }
                        current = value.location
                    }
                    .onEnded { _ in
                        if let rect, rect.width >= 16, rect.height >= 16 {
                            onDone(rect)
                        } else {
                            onCancel()
                        }
                    }
            )
        }
        .ignoresSafeArea()
    }
}
