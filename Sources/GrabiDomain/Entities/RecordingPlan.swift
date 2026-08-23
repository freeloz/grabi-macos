import Foundation

/// Everything the engine needs to know to capture: the sources, the target,
/// the devices and the size. It is a value, so a use case can build one,
/// compare it, or hand it to a fake in a test without any framework.
public struct RecordingPlan: Equatable, Sendable {
    public var sources: SourceSelection
    public var target: CaptureTarget
    public var devices: DeviceSelection
    public var cameraLayout: CameraLayout
    public var targetWidth: Int
    public var framesPerSecond: Int
    /// Where the file goes. nil for a preview: nothing is written.
    public var outputURL: URL?

    public init(sources: SourceSelection,
                target: CaptureTarget,
                devices: DeviceSelection,
                cameraLayout: CameraLayout,
                targetWidth: Int,
                framesPerSecond: Int,
                outputURL: URL?) {
        self.sources = sources
        self.target = target
        self.devices = devices
        self.cameraLayout = cameraLayout
        self.targetWidth = targetWidth
        self.framesPerSecond = framesPerSecond
        self.outputURL = outputURL
    }

    public var isPreview: Bool { outputURL == nil }

    /// The preview is for framing: small, slow, and without the microphone
    /// (that has its own monitoring session). System audio stays so its
    /// level meter shows something real.
    public static func preview(sources: SourceSelection,
                               target: CaptureTarget,
                               devices: DeviceSelection,
                               cameraLayout: CameraLayout,
                               quality: RecordingQuality) -> RecordingPlan {
        var previewSources = sources
        previewSources.microphone = false
        return RecordingPlan(
            sources: previewSources,
            target: target,
            devices: devices,
            cameraLayout: cameraLayout,
            targetWidth: min(quality.targetWidth, PreviewBudget.width),
            framesPerSecond: PreviewBudget.framesPerSecond,
            outputURL: nil)
    }

    public static func recording(sources: SourceSelection,
                                 target: CaptureTarget,
                                 devices: DeviceSelection,
                                 cameraLayout: CameraLayout,
                                 quality: RecordingQuality,
                                 outputURL: URL) -> RecordingPlan {
        RecordingPlan(
            sources: sources,
            target: target,
            devices: devices,
            cameraLayout: cameraLayout,
            targetWidth: quality.targetWidth,
            framesPerSecond: 30,
            outputURL: outputURL)
    }
}

/// Names the recordings deliberately the same in every language: the folder
/// and the file must not change when the user switches language.
public enum RecordingNaming {
    public static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Grabi \(formatter.string(from: date)).mov"
    }
}
