import Foundation
import CoreImage
import CoreVideo
import Metal

/// Compone la cámara como picture-in-picture sobre el frame de pantalla,
/// en GPU vía Core Image + Metal (nunca ventanas superpuestas).
///
/// Modelo de sincronización: los frames de PANTALLA marcan el ritmo del video.
/// La cámara solo va actualizando "su último frame" (ver `LatestFrameBox` en
/// el motor), y aquí se estampa el más reciente sobre cada frame de pantalla.
/// El desfase máximo es ~1 frame de cámara (~33 ms), imperceptible, y evita
/// tener que re-muestrear dos streams de video a un reloj común.
final class PiPCompositor {
    private let ciContext: CIContext
    private var pool: CVPixelBufferPool?
    private let width: Int
    private let height: Int
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Fracción del ancho total que ocupa el PiP.
    private let pipWidthFraction: CGFloat = 0.22
    private let pipMargin: CGFloat = 24

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
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

    /// Devuelve un buffer nuevo con la pantalla y, si hay, la cámara en la
    /// esquina inferior derecha. Si `camera` es nil (aún no llegó el primer
    /// frame de cámara), devuelve la pantalla sola.
    func compose(screen: CVPixelBuffer, camera: CVPixelBuffer?) -> CVPixelBuffer? {
        guard let pool else { return nil }
        var outBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outBuffer)
        guard let outBuffer else { return nil }

        var image = CIImage(cvPixelBuffer: screen)

        if let camera {
            let cam = CIImage(cvPixelBuffer: camera)
            let targetWidth = CGFloat(width) * pipWidthFraction
            let scale = targetWidth / cam.extent.width
            let scaled = cam.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            // Coordenadas Core Image: origen abajo-izquierda → esquina
            // inferior derecha con margen.
            let x = CGFloat(width) - scaled.extent.width - pipMargin
            let y = pipMargin
            let placed = scaled.transformed(by: CGAffineTransform(
                translationX: x - scaled.extent.origin.x,
                y: y - scaled.extent.origin.y))
            image = placed.composited(over: image)
        }

        ciContext.render(
            image,
            to: outBuffer,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: colorSpace)
        return outBuffer
    }
}
