import Foundation
import CoreImage
import CoreVideo
import CoreGraphics
import Metal

/// Compone la cámara sobre el frame de pantalla en GPU (Core Image + Metal),
/// con la forma (círculo / cuadrado / rectángulo redondeado), posición y
/// tamaño definidos por un `CameraLayout` que puede cambiar EN VIVO.
///
/// Modelo de sincronización: los frames de PANTALLA marcan el ritmo del video.
/// La cámara solo va actualizando "su último frame" y aquí se estampa el más
/// reciente sobre cada frame de pantalla. El desfase máximo es ~1 frame de
/// cámara (~33 ms), imperceptible, y evita re-muestrear dos streams de video.
final class PiPCompositor {
    private let ciContext: CIContext
    private var pool: CVPixelBufferPool?
    let width: Int
    let height: Int
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    // El layout lo escribe la UI (vía el motor) y lo lee la cola de video de
    // SCStream en cada frame: un lock corto es suficiente y sin contención.
    private let layoutLock = NSLock()
    private var _layout: CameraLayout

    var layout: CameraLayout {
        get { layoutLock.lock(); defer { layoutLock.unlock() }; return _layout }
        set { layoutLock.lock(); defer { layoutLock.unlock() }; _layout = newValue }
    }

    // Máscara cacheada: regenerarla solo cuando cambian forma o tamaño en px.
    private var cachedMask: CIImage?
    private var cachedMaskKey: String = ""

    init(width: Int, height: Int, layout: CameraLayout) {
        self.width = width
        self.height = height
        self._layout = layout
        if let device = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: device)
        } else {
            ciContext = CIContext()
        }
        let poolAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            // IOSurface para que GPU (Core Image) y encoder (VideoToolbox)
            // compartan el buffer sin copias.
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        CVPixelBufferPoolCreate(nil, nil, poolAttrs as CFDictionary, &pool)
    }

    /// Pantalla + cámara (si hay) → buffer nuevo listo para encoder/preview.
    func compose(screen: CVPixelBuffer, camera: CVPixelBuffer?) -> CVPixelBuffer? {
        guard let pool else { return nil }
        var outBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outBuffer)
        guard let outBuffer else { return nil }

        var image = CIImage(cvPixelBuffer: screen)
        // Si el frame de pantalla no coincide con el lienzo (p. ej. una
        // ventana que cambió de tamaño), se escala para llenar el ancho.
        if Int(image.extent.width) != width || Int(image.extent.height) != height {
            let sx = CGFloat(width) / image.extent.width
            let sy = CGFloat(height) / image.extent.height
            let s = min(sx, sy)
            image = image.transformed(by: CGAffineTransform(scaleX: s, y: s))
        }

        if let camera {
            let placed = shapedCamera(from: camera, layout: layout)
            image = placed.composited(over: image)
        }

        ciContext.render(
            image,
            to: outBuffer,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: colorSpace)
        return outBuffer
    }

    /// Cámara → recorte centrado al aspecto de la forma, escala al tamaño del
    /// layout, máscara de forma y traslado a su posición (coordenadas CI:
    /// origen abajo-izquierda; el layout usa arriba-izquierda como la UI).
    private func shapedCamera(from camera: CVPixelBuffer, layout: CameraLayout) -> CIImage {
        let cam = CIImage(cvPixelBuffer: camera)

        let pipHeight = max(16, CGFloat(height) * layout.height)
        let pipWidth = pipHeight * layout.shape.aspectRatio

        // Recorte centrado (aspect-fill) al aspecto de la forma.
        let sourceAspect = cam.extent.width / cam.extent.height
        let targetAspect = pipWidth / pipHeight
        var crop = cam.extent
        if sourceAspect > targetAspect {
            let newWidth = cam.extent.height * targetAspect
            crop.origin.x += (cam.extent.width - newWidth) / 2
            crop.size.width = newWidth
        } else {
            let newHeight = cam.extent.width / targetAspect
            crop.origin.y += (cam.extent.height - newHeight) / 2
            crop.size.height = newHeight
        }
        var image = cam.cropped(to: crop)

        let scale = pipWidth / crop.width
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // A origen (0,0) para aplicar la máscara y luego colocar.
        image = image.transformed(by: CGAffineTransform(
            translationX: -image.extent.origin.x,
            y: -image.extent.origin.y))

        let mask = shapeMask(width: pipWidth, height: pipHeight, layout: layout)
        if let masked = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: image,
            kCIInputMaskImageKey: mask,
        ])?.outputImage {
            image = masked.cropped(to: CGRect(x: 0, y: 0, width: pipWidth, height: pipHeight))
        }

        let x = CGFloat(width) * layout.origin.x
        let yTop = CGFloat(height) * layout.origin.y
        let y = CGFloat(height) - yTop - pipHeight // inversión de eje Y
        return image.transformed(by: CGAffineTransform(translationX: x, y: y))
    }

    /// Máscara blanca sobre transparente con la forma del layout, cacheada.
    private func shapeMask(width w: CGFloat, height h: CGFloat, layout: CameraLayout) -> CIImage {
        let key = "\(layout.shape.rawValue)-\(Int(w))x\(Int(h))"
        if key == cachedMaskKey, let cachedMask { return cachedMask }

        let size = CGSize(width: w, height: h)
        let radius = h * layout.cornerRadiusFraction
        let context = CGContext(
            data: nil, width: Int(w), height: Int(h),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.setFillColor(gray: 1, alpha: 1)
        let rect = CGRect(origin: .zero, size: size)
        if layout.shape == .circle {
            context.fillEllipse(in: rect)
        } else {
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
        }
        guard let cgImage = context.makeImage() else { return CIImage.empty() }
        let mask = CIImage(cgImage: cgImage)
        cachedMask = mask
        cachedMaskKey = key
        return mask
    }
}
