import Foundation
import CoreImage
import CoreVideo
import CoreGraphics
import Metal

/// Composites the camera over the screen frame on the GPU (Core Image +
/// Metal), with the shape (circle / square / rounded rectangle), position and
/// size defined by a `CameraLayout` that can change LIVE.
///
/// Synchronization model: SCREEN frames set the pace of the video.
/// The camera just keeps updating "its latest frame" and here the most
/// recent one is stamped onto each screen frame. The maximum lag is ~1
/// camera frame (~33 ms), imperceptible, and it avoids resampling two
/// video streams.
final class PiPCompositor {
    private let ciContext: CIContext
    private var pool: CVPixelBufferPool?
    let width: Int
    let height: Int
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    // The layout is written by the UI (via the engine) and read by SCStream's
    // video queue on every frame: a short lock suffices, with no contention.
    private let layoutLock = NSLock()
    private var _layout: CameraLayout

    var layout: CameraLayout {
        get { layoutLock.lock(); defer { layoutLock.unlock() }; return _layout }
        set { layoutLock.lock(); defer { layoutLock.unlock() }; _layout = newValue }
    }

    // Cached mask: regenerate it only when the shape or pixel size changes.
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
            // IOSurface so the GPU (Core Image) and encoder (VideoToolbox)
            // share the buffer without copies.
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        CVPixelBufferPoolCreate(nil, nil, poolAttrs as CFDictionary, &pool)
    }

    /// Screen + camera (if any) → new buffer ready for the encoder/preview.
    ///
    /// `screenContentRect` (pixels, top-left origin): rect of the actual
    /// content within the buffer when SCStream doesn't fill it (window
    /// capture). It's cropped and scaled to the canvas, centered over black —
    /// so the PiP camera always stays INSIDE the recorded content.
    func compose(screen: CVPixelBuffer, screenContentRect: CGRect? = nil, camera: CVPixelBuffer?) -> CVPixelBuffer? {
        guard let pool else { return nil }
        var outBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outBuffer)
        guard let outBuffer else { return nil }

        var image = CIImage(cvPixelBuffer: screen)

        if let rect = screenContentRect {
            // contentRect comes with a top-left origin; Core Image uses
            // a bottom-left origin.
            let bufferHeight = image.extent.height
            let ciRect = CGRect(x: rect.origin.x,
                                y: bufferHeight - rect.maxY,
                                width: rect.width,
                                height: rect.height)
                .integral.intersection(image.extent)
            if !ciRect.isEmpty {
                image = image.cropped(to: ciRect)
                    .transformed(by: CGAffineTransform(translationX: -ciRect.origin.x, y: -ciRect.origin.y))
            }
        }

        // Centered aspect-fit to the canvas (if the window resizes
        // mid-recording, it gets letterboxed without distortion).
        if Int(image.extent.width) != width || Int(image.extent.height) != height {
            let sx = CGFloat(width) / image.extent.width
            let sy = CGFloat(height) / image.extent.height
            let s = min(sx, sy)
            image = image.transformed(by: CGAffineTransform(scaleX: s, y: s))
            let dx = (CGFloat(width) - image.extent.width) / 2 - image.extent.origin.x
            let dy = (CGFloat(height) - image.extent.height) / 2 - image.extent.origin.y
            image = image.transformed(by: CGAffineTransform(translationX: dx, y: dy))
        }

        // Explicit black background: with letterboxing the pool buffer isn't
        // fully covered and could carry content from a previous frame.
        image = image.composited(over: CIImage(color: .black).cropped(
            to: CGRect(x: 0, y: 0, width: width, height: height)))

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

    /// Camera → centered crop to the shape's aspect, scale to the layout
    /// size, shape mask, and translate to its position (CI coordinates:
    /// bottom-left origin; the layout uses top-left like the UI).
    private func shapedCamera(from camera: CVPixelBuffer, layout: CameraLayout) -> CIImage {
        let cam = CIImage(cvPixelBuffer: camera)

        let pipHeight = max(16, CGFloat(height) * layout.height)
        let pipWidth = pipHeight * layout.shape.aspectRatio

        // Centered crop (aspect-fill) to the shape's aspect.
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

        // To origin (0,0) to apply the mask and then place.
        image = image.transformed(by: CGAffineTransform(
            translationX: -image.extent.origin.x,
            y: -image.extent.origin.y))

        // Mirror mode: the selfie looks like in a mirror (what feels
        // natural to the user facing the camera).
        image = image
            .transformed(by: CGAffineTransform(scaleX: -1, y: 1))
            .transformed(by: CGAffineTransform(translationX: pipWidth, y: 0))

        let mask = shapeMask(width: pipWidth, height: pipHeight, layout: layout)
        if let masked = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: image,
            kCIInputMaskImageKey: mask,
        ])?.outputImage {
            image = masked.cropped(to: CGRect(x: 0, y: 0, width: pipWidth, height: pipHeight))
        }

        let x = CGFloat(width) * layout.origin.x
        let yTop = CGFloat(height) * layout.origin.y
        let y = CGFloat(height) - yTop - pipHeight // Y-axis inversion
        return image.transformed(by: CGAffineTransform(translationX: x, y: y))
    }

    /// White-on-transparent mask with the layout's shape, cached.
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

/// Mirrors camera frames horizontally on the GPU, for camera-only mode
/// (at full screen the selfie is also mirrored).
final class MirrorRenderer {
    private let ciContext: CIContext
    private var pool: CVPixelBufferPool?
    private let width: Int
    private let height: Int
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        if let device = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: device)
        } else {
            ciContext = CIContext()
        }
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
    }

    func mirrored(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        guard let pool else { return nil }
        var outBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outBuffer)
        guard let outBuffer else { return nil }
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        image = image
            .transformed(by: CGAffineTransform(scaleX: -1, y: 1))
            .transformed(by: CGAffineTransform(translationX: image.extent.width, y: 0))
        ciContext.render(image, to: outBuffer,
                         bounds: CGRect(x: 0, y: 0, width: width, height: height),
                         colorSpace: colorSpace)
        return outBuffer
    }
}
