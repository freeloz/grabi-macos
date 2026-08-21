import SwiftUI
import AppKit
import Combine
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
        panel.setContentSize(NSSize(width: 440, height: 64))
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - 220, y: f.maxY - 74))
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
                cameraToggle: (model.screenEnabled && model.cameraEnabled)
                    ? (isOn: !model.cameraHidden, action: { model.toggleCameraHidden() }) : nil,
                micToggle: model.micEnabled
                    ? (isOn: !model.micMuted, action: { model.toggleMicMuted() }) : nil,
                onPause: { model.togglePause() },
                onResume: { model.togglePause() },
                onStop: { Task { await model.stop() } })
                .padding(6)
                .fixedSize()
        }
    }
}

// MARK: - Borde de grabación
// Marco redondeado alrededor de lo que se está grabando (pantalla, ventana o
// región): siempre sabes qué área se ve. Click-through y excluido de la captura.

@MainActor
final class CaptureBorderWindowController {
    private var panel: NSPanel?

    func show(frame: NSRect) {
        if panel == nil {
            let p = makeFloatingPanel(level: .statusBar)
            p.ignoresMouseEvents = true // nunca estorba: los clics lo atraviesan
            p.contentView = NSHostingView(rootView: CaptureBorderView())
            panel = p
        }
        panel?.setFrame(frame, display: true)
        panel?.orderFrontRegardless()
    }

    func close() {
        panel?.orderOut(nil)
    }
}

private struct CaptureBorderView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: GrabiRadius.md)
            .strokeBorder(GrabiColor.rec, lineWidth: 3)
            .padding(1)
            .ignoresSafeArea()
    }
}

// MARK: - Recuadro flotante de la selfie durante la grabación
// La cámara en vivo, con su forma, EXCLUIDA de la captura, colocada en el
// mismo lugar donde se compone en el video. Arrastrarla mueve el PiP grabado
// en vivo: el recuadro ES la vista previa de lo que se está grabando.

@MainActor
final class CameraWindowController: NSObject {
    private var panel: NSPanel?
    private let renderView = PixelBufferNSView()
    private weak var model: GrabiAppModel?
    private var layoutCancellable: AnyCancellable?
    private var moveObserver: NSObjectProtocol?
    private var programmaticMove = false
    /// Área de captura en coordenadas NS (origen abajo-izquierda, globales);
    /// nil → sin mapeo (modo cámara-sola: libre).
    private var baseRect: NSRect?

    func show(model: GrabiAppModel) {
        self.model = model
        renderView.usesAspectFill = true // recorte centrado, como el PiP grabado
        model.engine.onCameraFrame = { [weak self] pixelBuffer in
            DispatchQueue.main.async { self?.renderView.render(pixelBuffer) }
        }
        if panel == nil {
            let p = makeFloatingPanel(level: .statusBar)
            p.isMovableByWindowBackground = true
            p.hasShadow = true
            p.contentView = NSHostingView(rootView: CameraFloatView(
                model: model,
                renderView: renderView,
                onResizeBegan: { [weak self] in self?.beginResize() },
                onResizeChanged: { [weak self] delta, corner in self?.resize(by: delta, corner: corner) }))
            panel = p
            moveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: p, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.windowMoved() }
            }
        }
        baseRect = computeBaseRect()
        applyLayout()
        panel?.orderFrontRegardless()

        // Seguir cambios de forma/tamaño/posición hechos desde otro lado
        // (ventana de vista previa, menú contextual).
        layoutCancellable = model.$cameraLayout
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyLayout() }
    }

    func close() {
        layoutCancellable = nil
        panel?.orderOut(nil)
    }

    /// Rect de lo capturado, en coordenadas de pantalla NS.
    private func computeBaseRect() -> NSRect? {
        model?.captureAreaFrame()
    }

    private func applyLayout() {
        guard let panel, let model else { return }
        let layout = model.cameraLayout
        programmaticMove = true
        defer { programmaticMove = false }

        if let base = baseRect {
            let h = base.height * layout.height
            let w = h * layout.shape.aspectRatio
            let x = base.minX + base.width * layout.origin.x
            let y = base.maxY - base.height * layout.origin.y - h
            panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        } else if let screen = NSScreen.main {
            // Cámara-sola: tamaño fijo abajo a la derecha, libre de mover.
            let h: CGFloat = 220
            let w = h * layout.shape.aspectRatio
            if panel.frame.width < 10 { // primera vez
                panel.setFrame(NSRect(x: screen.visibleFrame.maxX - w - 24,
                                      y: screen.visibleFrame.minY + 24,
                                      width: w, height: h), display: true)
            } else {
                var f = panel.frame
                f.size = NSSize(width: w, height: h)
                panel.setFrame(f, display: true)
            }
        }
    }

    // MARK: Redimensionar desde cualquier esquina (ancla: la esquina opuesta)

    private var resizeStartLayout: (origin: CGPoint, height: CGFloat)?
    private var resizeStartFrame: NSRect?

    private func beginResize() {
        resizeStartLayout = model.map { ($0.cameraLayout.origin, $0.cameraLayout.height) }
        resizeStartFrame = panel?.frame
    }

    /// En modo mapeado actualiza `cameraLayout` → el PiP grabado cambia de
    /// tamaño en vivo; la esquina opuesta a la arrastrada queda fija.
    private func resize(by delta: CGFloat, corner: ResizeCorner) {
        guard let model else { return }
        let aspect = model.cameraLayout.shape.aspectRatio

        if let base = baseRect, let start = resizeStartLayout {
            // Mismo rango que la vista previa (prototipo: s 80–210 sobre 360).
            let newHeight = min(max(start.height + delta / base.height, 80.0 / 360.0), 210.0 / 360.0)
            let dH = start.height - newHeight
            let dW = dH * aspect * base.height / base.width
            var origin = start.origin
            switch corner {
            case .bottomRight: break
            case .bottomLeft: origin.x += dW
            case .topRight: origin.y += dH
            case .topLeft: origin.x += dW; origin.y += dH
            }
            let wFrac = newHeight * aspect * base.height / base.width
            origin.x = min(max(origin.x, 0), max(0, 1 - wFrac))
            origin.y = min(max(origin.y, 0), max(0, 1 - newHeight))
            model.cameraLayout = CameraLayout(shape: model.cameraLayout.shape, origin: origin, height: newHeight)
            // applyLayout() llega vía la suscripción a $cameraLayout.
        } else if let panel, let f0 = resizeStartFrame {
            // Cámara-sola: solo cambia la ventana flotante (coords NS: y hacia
            // arriba; "topLeft" visual = (minX, maxY)).
            let h = min(max(f0.height + delta, 140), 420)
            let w = h * aspect
            let newFrame: NSRect
            switch corner {
            case .bottomRight: newFrame = NSRect(x: f0.minX, y: f0.maxY - h, width: w, height: h)
            case .bottomLeft: newFrame = NSRect(x: f0.maxX - w, y: f0.maxY - h, width: w, height: h)
            case .topRight: newFrame = NSRect(x: f0.minX, y: f0.minY, width: w, height: h)
            case .topLeft: newFrame = NSRect(x: f0.maxX - w, y: f0.minY, width: w, height: h)
            }
            programmaticMove = true
            panel.setFrame(newFrame, display: true)
            programmaticMove = false
        }
    }

    /// El usuario arrastró el recuadro → mover el PiP grabado en vivo.
    private func windowMoved() {
        guard !programmaticMove, let panel, let base = baseRect, let model else { return }
        let f = panel.frame
        let wFrac = f.width / base.width
        let hFrac = f.height / base.height
        var x = (f.minX - base.minX) / base.width
        var y = (base.maxY - f.maxY) / base.height
        x = min(max(x, 0), max(0, 1 - wFrac))
        y = min(max(y, 0), max(0, 1 - hFrac))
        // Evitar el eco: cameraLayout.didSet re-aplica el frame.
        programmaticMove = true
        model.cameraLayout.origin = CGPoint(x: x, y: y)
        programmaticMove = false
    }
}

/// Esquina de redimensión (nombres visuales: topLeft = arriba-izquierda).
enum ResizeCorner {
    case topLeft, topRight, bottomLeft, bottomRight

    /// Crecimiento a partir del arrastre: hacia afuera = agrandar.
    func delta(from translation: CGSize) -> CGFloat {
        switch self {
        case .bottomRight: return max(translation.width, translation.height)
        case .bottomLeft: return max(-translation.width, translation.height)
        case .topRight: return max(translation.width, -translation.height)
        case .topLeft: return max(-translation.width, -translation.height)
        }
    }

    var alignment: Alignment {
        switch self {
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }
}

private struct CameraFloatView: View {
    @ObservedObject var model: GrabiAppModel
    let renderView: PixelBufferNSView
    let onResizeBegan: () -> Void
    let onResizeChanged: (CGFloat, ResizeCorner) -> Void

    @State private var hovering = false
    @State private var resizingCorner: ResizeCorner?

    var body: some View {
        let layout = model.cameraLayout
        GeometryReader { geo in
            let radius = layout.shape == .circle
                ? geo.size.height / 2
                : geo.size.height * layout.cornerRadiusFraction
            CameraPixelView(view: renderView)
                .scaleEffect(x: -1, y: 1) // modo espejo, igual que lo grabado
                .clipShape(RoundedRectangle(cornerRadius: radius))
                .contextMenu {
                    ForEach(CameraShape.allCases) { shape in
                        Button(shape.displayName) { model.cameraLayout.shape = shape }
                    }
                }
                // Mover: arrastra desde dentro del cuadro (la ventana es
                // movable-by-background). Redimensionar: cualquier esquina.
                .overlay {
                    ForEach([ResizeCorner.topLeft, .topRight, .bottomLeft, .bottomRight], id: \.self) { corner in
                        cornerHandle(corner, circleInset: layout.shape == .circle ? geo.size.height * 0.10 : 4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
                    }
                }
                .onHover { hovering = $0 }
                .animation(GrabiAnimation.standard(GrabiDuration.fast), value: hovering)
        }
        .ignoresSafeArea()
    }

    /// Manija de esquina: visible al pasar el cursor, área de golpeo de 30 px.
    private func cornerHandle(_ corner: ResizeCorner, circleInset: CGFloat) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().strokeBorder(GrabiColor.brandStrong, lineWidth: 2))
            .frame(width: 13, height: 13)
            .opacity(hovering || resizingCorner != nil ? 1 : 0)
            .frame(width: 30, height: 30)
            .contentShape(Circle())
            .padding(circleInset)
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        if resizingCorner == nil {
                            resizingCorner = corner
                            onResizeBegan()
                        }
                        onResizeChanged(corner.delta(from: value.translation), corner)
                    }
                    .onEnded { _ in resizingCorner = nil }
            )
    }
}

private struct CameraPixelView: NSViewRepresentable {
    let view: PixelBufferNSView
    func makeNSView(context: Context) -> PixelBufferNSView { view }
    func updateNSView(_ nsView: PixelBufferNSView, context: Context) {}
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
    private var panels: [NSPanel] = []
    private var keyMonitor: Any?
    private weak var model: GrabiAppModel?

    /// Un overlay POR PANTALLA: el usuario dibuja en la que quiera y esa
    /// pantalla queda seleccionada. Los paneles se crean de cero en cada
    /// apertura para que el arrastre anterior no contamine el nuevo (el
    /// estado del gesto vive en la vista).
    func show(model: GrabiAppModel) {
        self.model = model
        closePanels()

        for screen in NSScreen.screens {
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            let panel = makeFloatingPanel(level: .screenSaver)
            panel.contentView = NSHostingView(rootView: RegionPickView(
                onDone: { [weak self] rect in self?.finish(rect: rect, displayID: displayID) },
                onCancel: { [weak self] in self?.finish(rect: nil, displayID: nil) }))
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        // Esc cancela.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.finish(rect: nil, displayID: nil); return nil }
            return event
        }
    }

    private func closePanels() {
        panels.forEach { $0.orderOut(nil) }
        panels = []
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func finish(rect: CGRect?, displayID: CGDirectDisplayID?) {
        closePanels()
        guard let model else { return }
        if let rect {
            model.regionRect = rect
            if let displayID {
                model.selectedDisplayID = displayID == CGMainDisplayID() ? nil : displayID
            }
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
                        Text(L("app.region.titulo"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(L("app.region.esc"))
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
