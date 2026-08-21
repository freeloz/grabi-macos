import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreGraphics

/// Captures display/window/region and/or system audio with ScreenCaptureKit.
///
/// Usage: `prepare(...)` resolves the filter and returns the output size
/// (the engine needs it BEFORE creating the writer/compositor); `start()`
/// starts the stream.
///
/// Notes:
/// - System audio is captured with the SAME SCStream as the video.
///   When only audio is requested, we don't register the video output and
///   ask for minimal frames.
/// - The app's own windows (floating controls, preview) are excluded
///   from display/region capture via `excludingApplications`.
///   Not applicable to window capture: only the chosen window is visible.
final class ScreenCapturer: NSObject, SCStreamOutput, SCStreamDelegate {
    /// (buffer, PTS, rect of the actual content in PIXELS within the buffer).
    /// In window capture SCStream does not always fill the buffer: it draws
    /// the window in a corner and leaves the rest empty. The rect (from each
    /// frame's contentRect × scaleFactor attachments) allows cropping just
    /// the content; nil → the frame fills the buffer.
    var onVideoFrame: ((CVPixelBuffer, CMTime, CGRect?) -> Void)?
    var onSystemAudio: ((CMSampleBuffer) -> Void)?
    /// The stream stopped on its own (e.g. permission revoked or window closed).
    var onFatalError: ((Error) -> Void)?

    private var stream: SCStream?
    private var filter: SCContentFilter?
    private var configuration: SCStreamConfiguration?
    private let videoQueue = DispatchQueue(label: "record.screen.video")
    private let audioQueue = DispatchQueue(label: "record.screen.audio")
    private var stopping = false

    private(set) var outputSize: (width: Int, height: Int) = (2, 2)

    /// Resolves the target against the shareable content, builds the filter
    /// and configuration, and returns the video's output size.
    func prepare(target: CaptureTarget,
                 targetWidth: Int,
                 fps: Int,
                 captureVideo: Bool,
                 captureAudio: Bool) async throws -> (width: Int, height: Int) {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw RecordingError.screenPermissionDenied
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == ownPID }

        func resolveDisplay(_ id: CGDirectDisplayID?) throws -> SCDisplay {
            let wanted = id ?? CGMainDisplayID()
            guard let display = content.displays.first(where: { $0.displayID == wanted }) ?? content.displays.first else {
                throw RecordingError.displayNotFound
            }
            return display
        }

        /// Even-numbered size that keeps the aspect, with `targetWidth` as max
        /// width (narrower content is captured at 2x native for sharpness).
        func fittedSize(pointWidth: CGFloat, pointHeight: CGFloat) -> (Int, Int) {
            guard pointWidth > 0, pointHeight > 0 else { return (targetWidth, targetWidth * 9 / 16) }
            let pixelWidth = min(CGFloat(targetWidth), pointWidth * 2)
            var w = Int(pixelWidth.rounded()); w -= w % 2
            var h = Int((pixelWidth * pointHeight / pointWidth).rounded()); h -= h % 2
            return (max(w, 2), max(h, 2))
        }

        let filter: SCContentFilter
        var size = (width: 2, height: 2)

        switch target {
        case .display(let id):
            let display = try resolveDisplay(id)
            filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            size = fittedSize(pointWidth: CGFloat(display.width), pointHeight: CGFloat(display.height))
        case .window(let windowID):
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw RecordingError.windowNotFound
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            size = fittedSize(pointWidth: window.frame.width, pointHeight: window.frame.height)
        case .region(let id, let rect):
            guard rect.width >= 16, rect.height >= 16 else { throw RecordingError.invalidRegion }
            let display = try resolveDisplay(id)
            filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            size = fittedSize(pointWidth: rect.width, pointHeight: rect.height)
        }

        let config = SCStreamConfiguration()
        if captureVideo {
            config.width = size.width
            config.height = size.height
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = true
            config.queueDepth = 6
            if case .region(_, let rect) = target {
                config.sourceRect = rect
            }
        } else {
            // System audio only: minimal video stream that we ignore.
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 5)
            size = (2, 2)
        }
        if captureAudio {
            config.capturesAudio = true
            config.sampleRate = 48_000
            config.channelCount = 2
            config.excludesCurrentProcessAudio = true
        }

        self.filter = filter
        self.configuration = config
        self.outputSize = size
        return size
    }

    /// Starts the capture. Requires a prior `prepare(...)`.
    func start(captureVideo: Bool, captureAudio: Bool) async throws {
        guard let filter, let configuration else {
            throw RecordingError.invalidState("ScreenCapturer.start without prior prepare")
        }
        stopping = false
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        if captureVideo {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        }
        if captureAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        }
        do {
            try await stream.startCapture()
        } catch {
            throw RecordingError.captureInterrupted("could not start screen capture: \(error.localizedDescription)")
        }
        self.stream = stream
    }

    func stop() async {
        stopping = true
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .screen:
            // SCStream also emits "idle"/incomplete frames without an image;
            // only the complete ones matter.
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let info = attachments.first,
                  let statusRaw = info[.status] as? Int,
                  statusRaw == SCFrameStatus.complete.rawValue,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
            else { return }

            // Rect of the actual content, in buffer pixels.
            var contentRect: CGRect?
            if let rectDict = info[.contentRect] as? NSDictionary,
               let rect = CGRect(dictionaryRepresentation: rectDict as CFDictionary),
               let scaleFactor = info[.scaleFactor] as? CGFloat, scaleFactor > 0 {
                let pixelRect = CGRect(
                    x: rect.origin.x * scaleFactor,
                    y: rect.origin.y * scaleFactor,
                    width: rect.width * scaleFactor,
                    height: rect.height * scaleFactor)
                let bufferRect = CGRect(x: 0, y: 0,
                                        width: CVPixelBufferGetWidth(pixelBuffer),
                                        height: CVPixelBufferGetHeight(pixelBuffer))
                let clipped = pixelRect.intersection(bufferRect)
                // Only relevant if the content does NOT fill the buffer.
                if !clipped.isEmpty, clipped.size != bufferRect.size {
                    contentRect = clipped
                }
            }
            onVideoFrame?(pixelBuffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer), contentRect)
        case .audio:
            onSystemAudio?(sampleBuffer)
        default:
            // .microphone (macOS 15+) is not used: the mic goes through AVFoundation.
            break
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard !stopping else { return }
        onFatalError?(error)
    }
}
