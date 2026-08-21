import SwiftUI
import AppKit
import CoreVideo
import RecordEngine
import RecordUI

/// Ventana "Vista previa — Grabi" (Fase 3 §02): lo que ves es lo que se
/// graba. La cámara se arrastra libremente, se redimensiona desde la esquina
/// inferior derecha y cambia de forma con clic derecho o desde la barra.
/// Queda excluida de la grabación (ventana de la propia app).
@MainActor
final class PreviewWindowController: NSObject, ObservableObject, NSWindowDelegate {
    private var window: NSWindow?
    let renderView = PixelBufferNSView()
    /// Tamaño del último frame (para mapear el overlay al área real del video).
    @Published var videoSize = CGSize(width: 16, height: 10)
    private weak var model: GrabiAppModel?

    var isVisible: Bool { window?.isVisible ?? false }

    func show(model: GrabiAppModel) {
        self.model = model
        model.engine.onPreviewFrame = { [weak self] pixelBuffer in
            DispatchQueue.main.async {
                guard let self else { return }
                let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                                  height: CVPixelBufferGetHeight(pixelBuffer))
                if size != self.videoSize { self.videoSize = size }
                self.renderView.render(pixelBuffer)
            }
        }
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 470),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            win.title = L("app.preview.title")
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.contentView = NSHostingView(rootView: PreviewRoot(model: model, controller: self))
            win.center()
            window = win
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        model?.previewClosed()
    }
}

/// NSView cuyo layer muestra CVPixelBuffers (IOSurface) sin copias.
final class PixelBufferNSView: NSView {
    private let contentLayer = CALayer()

    /// true → recorte centrado (aspect-fill), como la cámara del PiP.
    var usesAspectFill = false {
        didSet { contentLayer.contentsGravity = usesAspectFill ? .resizeAspectFill : .resizeAspect }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .black
        contentLayer.contentsGravity = .resizeAspect
        contentLayer.masksToBounds = true
        layer?.addSublayer(contentLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.frame = bounds
        CATransaction.commit()
    }

    func render(_ pixelBuffer: CVPixelBuffer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() {
            contentLayer.contents = surface
        }
        CATransaction.commit()
    }
}

private struct PixelBufferView: NSViewRepresentable {
    let view: PixelBufferNSView
    func makeNSView(context: Context) -> PixelBufferNSView { view }
    func updateNSView(_ nsView: PixelBufferNSView, context: Context) {}
}

struct PreviewRoot: View {
    @ObservedObject var model: GrabiAppModel
    @ObservedObject var controller: PreviewWindowController

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let fitted = fittedRect(in: geo.size)
                ZStack(alignment: .topLeading) {
                    PixelBufferView(view: controller.renderView)
                    if model.screenEnabled, model.cameraEnabled {
                        CameraOverlay(model: model, contentRect: fitted)
                    }
                }
            }
            .background(Color.black)
            bottomBar
        }
        .frame(minWidth: 560, minHeight: 380)
        .background(GrabiColor.bg)
    }

    /// Rect del video dentro de la vista (el layer usa resizeAspect).
    private func fittedRect(in size: CGSize) -> CGRect {
        let videoAspect = controller.videoSize.width / max(controller.videoSize.height, 1)
        let viewAspect = size.width / max(size.height, 1)
        if videoAspect > viewAspect {
            let h = size.width / videoAspect
            return CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h)
        } else {
            let w = size.height * videoAspect
            return CGRect(x: (size.width - w) / 2, y: 0, width: w, height: size.height)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: GrabiSpace.s3) {
            GrabiSegmented(items: CameraShape.allCases.map {
                GrabiSegmentItem($0, icon: .forShape($0))
            }, selection: Binding(
                get: { model.cameraLayout.shape },
                set: { model.cameraLayout.shape = $0 }
            ))
            .disabled(!model.cameraEnabled)
            Text(L("app.preview.hint"))
                .font(.system(size: 12))
                .foregroundStyle(GrabiColor.textSecondary)
                .lineLimit(2)
            Spacer(minLength: GrabiSpace.s2)
            if model.isActive {
                RecBadge(elapsed: model.elapsedText)
            } else {
                Button { model.requestStart() } label: {
                    HStack(spacing: 9) {
                        SemaforoDot(model.anySourceEnabled ? .listo : .apagado, size: 11)
                        Text(L("app.preview.record")).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(GrabiColor.text)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .background(GrabiColor.surface)
                    .overlay(Capsule().strokeBorder(GrabiColor.borderStrong, lineWidth: 1.5))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!model.anySourceEnabled)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(GrabiColor.surface)
        .overlay(Rectangle().fill(GrabiColor.border).frame(height: 1), alignment: .top)
    }
}

/// La cámara en la vista previa: arrastrable con imanes a esquinas/bordes,
/// redimensionable desde la esquina inferior derecha (proporción fija),
/// borde brand + 4 manijas, menú contextual de formas.
private struct CameraOverlay: View {
    @ObservedObject var model: GrabiAppModel
    let contentRect: CGRect

    @State private var dragStartOrigin: CGPoint?
    @State private var resizeStart: (origin: CGPoint, height: CGFloat)?

    /// Margen alrededor del recuadro para que las manijas (centradas en las
    /// esquinas) queden DENTRO del área interactiva del overlay.
    private let handlePad: CGFloat = 15

    var body: some View {
        let layout = model.cameraLayout
        let pipHeight = contentRect.height * layout.height
        let pipWidth = pipHeight * layout.shape.aspectRatio
        let x = contentRect.origin.x + contentRect.width * layout.origin.x
        let y = contentRect.origin.y + contentRect.height * layout.origin.y
        let cornerRadius = layout.shape == .circle ? pipHeight / 2 : pipHeight * layout.cornerRadiusFraction

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(GrabiColor.brandStrong, lineWidth: 2.5)
                .frame(width: pipWidth, height: pipHeight)
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
                .gesture(dragGesture(pipWidth: pipWidth, pipHeight: pipHeight))
            // 4 manijas de esquina: todas redimensionan, con ancla en la
            // esquina opuesta (Fase 3 §02).
            resizeHandle(.topLeft, at: CGPoint(x: handlePad, y: handlePad))
            resizeHandle(.topRight, at: CGPoint(x: handlePad + pipWidth, y: handlePad))
            resizeHandle(.bottomLeft, at: CGPoint(x: handlePad, y: handlePad + pipHeight))
            resizeHandle(.bottomRight, at: CGPoint(x: handlePad + pipWidth, y: handlePad + pipHeight))
        }
        .frame(width: pipWidth + handlePad * 2, height: pipHeight + handlePad * 2)
        .offset(x: x - handlePad, y: y - handlePad)
        .contextMenu {
            ForEach(CameraShape.allCases) { shape in
                Button {
                    model.cameraLayout.shape = shape
                } label: {
                    if shape == model.cameraLayout.shape {
                        Label(shape.displayName, systemImage: "checkmark")
                    } else {
                        Text(shape.displayName)
                    }
                }
            }
            Divider()
            Button(L("app.camera.hide")) { model.cameraEnabled = false }
        }
    }

    private func resizeHandle(_ corner: ResizeCorner, at point: CGPoint) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().strokeBorder(GrabiColor.brandStrong, lineWidth: 2))
            .frame(width: 12, height: 12)
            // Área de golpeo de 30 px (mínimo 28 con puntero, Fase 2 §10):
            // la manija visible es pequeña pero fácil de agarrar.
            .frame(width: 30, height: 30)
            .contentShape(Circle())
            .position(point)
            .onHover { inside in
                if inside { NSCursor.crosshair.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if resizeStart == nil {
                            resizeStart = (model.cameraLayout.origin, model.cameraLayout.height)
                        }
                        guard let start = resizeStart else { return }
                        let delta = corner.delta(from: value.translation)
                        // Rango del prototipo: s 80–210 sobre lienzo de 360.
                        let newHeight = min(max(start.height + delta / contentRect.height, 80.0 / 360.0), 210.0 / 360.0)
                        // Ancla en la esquina opuesta a la arrastrada.
                        let aspect = model.cameraLayout.shape.aspectRatio
                        let dH = start.height - newHeight
                        let dW = dH * aspect * contentRect.height / contentRect.width
                        var origin = start.origin
                        switch corner {
                        case .bottomRight: break
                        case .bottomLeft: origin.x += dW
                        case .topRight: origin.y += dH
                        case .topLeft: origin.x += dW; origin.y += dH
                        }
                        let wFrac = newHeight * aspect * contentRect.height / max(contentRect.width, 1)
                        origin.x = min(max(origin.x, 0), max(0, 1 - wFrac))
                        origin.y = min(max(origin.y, 0), max(0, 1 - newHeight))
                        model.cameraLayout = CameraLayout(
                            shape: model.cameraLayout.shape, origin: origin, height: newHeight)
                    }
                    .onEnded { _ in resizeStart = nil }
            )
    }

    private func dragGesture(pipWidth: CGFloat, pipHeight: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartOrigin == nil { dragStartOrigin = model.cameraLayout.origin }
                guard let start = dragStartOrigin else { return }
                var newX = start.x + value.translation.width / contentRect.width
                var newY = start.y + value.translation.height / contentRect.height
                let wFrac = pipWidth / contentRect.width
                let hFrac = pipHeight / contentRect.height
                newX = min(max(newX, 0), 1 - wFrac)
                newY = min(max(newY, 0), 1 - hFrac)
                (newX, newY) = snapped(x: newX, y: newY, wFrac: wFrac, hFrac: hFrac)
                model.cameraLayout.origin = CGPoint(x: newX, y: newY)
            }
            .onEnded { _ in dragStartOrigin = nil }
    }

    /// Imanes a las 4 esquinas y al centro de cada borde, con margen space.6
    /// (24 sobre el lienzo de referencia 640×360 del prototipo).
    private func snapped(x: CGFloat, y: CGFloat, wFrac: CGFloat, hFrac: CGFloat) -> (CGFloat, CGFloat) {
        let marginX = 24.0 / 640.0
        let marginY = 24.0 / 360.0
        let threshold = 14.0 / max(contentRect.width, 1)
        let targetsX = [marginX, (1 - wFrac) / 2, 1 - wFrac - marginX]
        let targetsY = [marginY, (1 - hFrac) / 2, 1 - hFrac - marginY]
        var sx = x, sy = y
        for t in targetsX where abs(x - t) < threshold { sx = t; break }
        for t in targetsY where abs(y - t) < threshold * 2 { sy = t; break }
        return (sx, sy)
    }

    private func clampOrigin() {
        let layout = model.cameraLayout
        let wFrac = layout.height * layout.shape.aspectRatio * (contentRect.height / max(contentRect.width, 1))
        let hFrac = layout.height
        var origin = layout.origin
        origin.x = min(max(origin.x, 0), max(0, 1 - wFrac))
        origin.y = min(max(origin.y, 0), max(0, 1 - hFrac))
        if origin != layout.origin { model.cameraLayout.origin = origin }
    }
}
