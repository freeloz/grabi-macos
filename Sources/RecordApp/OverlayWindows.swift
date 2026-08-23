import SwiftUI
import AppKit
import Combine
import RecordEngine
import RecordUI
import GrabiDomain

/// Non-activating floating panel: base for the pill and overlays.
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

// MARK: - Floating pill (Phase 3 §03)

/// Appears while recording, draggable, always on top and EXCLUDED from the
/// capture (the engine excludes the app's own windows).
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

// MARK: - Recording border
// Rounded frame around what is being recorded (screen, window, or region):
// you always know which area is visible. Click-through and excluded from capture.

@MainActor
final class CaptureBorderWindowController {
    private var panel: NSPanel?

    func show(frame: NSRect) {
        if panel == nil {
            let p = makeFloatingPanel(level: .statusBar)
            p.ignoresMouseEvents = true // never in the way: clicks pass through it
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

// MARK: - Floating selfie frame during recording
// The live camera, with its shape, EXCLUDED from the capture, placed in the
// same spot where it is composited into the video. Dragging it moves the
// recorded PiP live: the frame IS the preview of what is being recorded.

@MainActor
final class CameraWindowController: NSObject {
    private var panel: NSPanel?
    private let renderView = PixelBufferNSView()
    private weak var model: GrabiAppModel?
    private var layoutCancellable: AnyCancellable?
    private var moveObserver: NSObjectProtocol?
    private var programmaticMove = false
    /// Capture area in NS coordinates (bottom-left origin, global);
    /// nil → no mapping (camera-only mode: free).
    private var baseRect: NSRect?

    func show(model: GrabiAppModel) {
        self.model = model
        renderView.usesAspectFill = true // centered crop, like the recorded PiP
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
                Task { @MainActor [weak self] in self?.windowMoved() }
            }
        }
        baseRect = computeBaseRect()
        applyLayout()
        panel?.orderFrontRegardless()

        // Track shape/size/position changes made from elsewhere
        // (preview window, context menu).
        layoutCancellable = model.$cameraLayout
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyLayout() }
    }

    func close() {
        layoutCancellable = nil
        panel?.orderOut(nil)
    }

    /// Rect of what is captured, in NS screen coordinates.
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
            // Camera-only: fixed size at the bottom right, free to move.
            let h: CGFloat = 220
            let w = h * layout.shape.aspectRatio
            if panel.frame.width < 10 { // first time
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

    // MARK: Resize from any corner (anchor: the opposite corner)

    private var resizeStartLayout: (origin: CGPoint, height: CGFloat)?
    private var resizeStartFrame: NSRect?

    private func beginResize() {
        resizeStartLayout = model.map { ($0.cameraLayout.origin, $0.cameraLayout.height) }
        resizeStartFrame = panel?.frame
    }

    /// In mapped mode updates `cameraLayout` → the recorded PiP resizes
    /// live; the corner opposite the dragged one stays fixed.
    private func resize(by delta: CGFloat, corner: ResizeCorner) {
        guard let model else { return }
        let aspect = model.cameraLayout.shape.aspectRatio

        if let base = baseRect, let start = resizeStartLayout {
            // Same range as the preview (prototype: s 80–210 over 360).
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
            // applyLayout() arrives via the $cameraLayout subscription.
        } else if let panel, let f0 = resizeStartFrame {
            // Camera-only: only the floating window changes (NS coords: y
            // upward; visual "topLeft" = (minX, maxY)).
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

    /// The user dragged the frame → move the recorded PiP live.
    private func windowMoved() {
        guard !programmaticMove, let panel, let base = baseRect, let model else { return }
        let f = panel.frame
        let wFrac = f.width / base.width
        let hFrac = f.height / base.height
        var x = (f.minX - base.minX) / base.width
        var y = (base.maxY - f.maxY) / base.height
        x = min(max(x, 0), max(0, 1 - wFrac))
        y = min(max(y, 0), max(0, 1 - hFrac))
        // Avoid the echo: cameraLayout.didSet re-applies the frame.
        programmaticMove = true
        model.cameraLayout.origin = CGPoint(x: x, y: y)
        programmaticMove = false
    }
}

/// Resize corner (visual names: topLeft = top-left).
enum ResizeCorner {
    case topLeft, topRight, bottomLeft, bottomRight

    /// Growth from the drag: outward = enlarge.
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
                .scaleEffect(x: -1, y: 1) // mirror mode, same as the recording
                .clipShape(RoundedRectangle(cornerRadius: radius))
                .contextMenu {
                    ForEach(CameraShape.allCases) { shape in
                        Button(shape.displayName) { model.cameraLayout.shape = shape }
                    }
                }
                // Move: drag from inside the frame (the window is
                // movable-by-background). Resize: any corner.
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

    /// Corner handle: visible on hover, 30 px hit area.
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

// MARK: - 3·2·1 countdown (Phase 3/4: mascot concentrating)

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
                MascotView(pose: .recording, size: 120)
                Text("\(model.countdown ?? 0)")
                    .font(.system(size: 88, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(nsColor: NSColor(srgbRed: 0xFA/255.0, green: 0xF7/255.0, blue: 0xF1/255.0, alpha: 1)))
                    .monospacedDigit()
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Region picker (Phase C §3): overlay to draw the rectangle

@MainActor
final class RegionPickerController: NSObject {
    private var panels: [NSPanel] = []
    private var keyMonitor: Any?
    private weak var model: GrabiAppModel?

    /// One overlay PER SCREEN: the user draws on whichever one they want
    /// and that screen becomes the selected one. The panels are created from
    /// scratch on every opening so the previous drag doesn't contaminate the
    /// new one (the gesture state lives in the view).
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
        // Esc cancels.
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
            model.captureMode = .screen
        }
    }
}

/// Draws the rectangle by dragging; local coordinates (top-left)
/// == `sourceRect` coordinates because the window covers the whole screen.
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
                // Veil with a cutout at the chosen region.
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
                        Text(L("app.region.title"))
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
