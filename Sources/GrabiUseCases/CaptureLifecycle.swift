import Foundation
import GrabiDomain

/// Who, right now, needs the camera / screen / microphone.
///
/// This is the rule that keeps the camera light honest: capture runs only
/// while a surface that shows it is on screen, and a recording always wins.
public struct CaptureDemand: Equatable, Sendable {
    /// A surface that renders the live preview is visible.
    public var previewVisible: Bool
    /// The menu bar panel is open (it shows the microphone level).
    public var panelOpen: Bool
    /// A recording owns the devices; nothing may release them.
    public var recordingActive: Bool
    public var sources: SourceSelection
    public var permissions: PermissionReport

    public init(previewVisible: Bool, panelOpen: Bool, recordingActive: Bool,
                sources: SourceSelection, permissions: PermissionReport) {
        self.previewVisible = previewVisible
        self.panelOpen = panelOpen
        self.recordingActive = recordingActive
        self.sources = sources
        self.permissions = permissions
    }
}

/// What the capture layer should be doing for a given demand.
public struct CaptureIntent: Equatable, Sendable {
    public let wantsPreview: Bool
    public let wantsMicrophoneMonitor: Bool

    public init(wantsPreview: Bool, wantsMicrophoneMonitor: Bool) {
        self.wantsPreview = wantsPreview
        self.wantsMicrophoneMonitor = wantsMicrophoneMonitor
    }

    public static let idle = CaptureIntent(wantsPreview: false, wantsMicrophoneMonitor: false)
}

/// Decides the intent (pure) and applies it (through the ports).
public struct SyncCaptureUseCase: Sendable {
    private let engine: CaptureEnginePort
    private let microphone: MicrophoneMonitorPort

    public init(engine: CaptureEnginePort, microphone: MicrophoneMonitorPort) {
        self.engine = engine
        self.microphone = microphone
    }

    /// Pure decision — the part worth testing.
    public static func intent(for demand: CaptureDemand) -> CaptureIntent {
        // A recording owns the devices: never touch them mid-take.
        guard !demand.recordingActive else { return .idle }
        let visible = demand.previewVisible || demand.panelOpen
        guard visible else { return .idle }
        let wantsPreview = demand.previewVisible
            && demand.sources.hasVideo
            && (demand.sources.screen ? demand.permissions.screen.isUsable : true)
        let wantsMic = demand.sources.microphone && demand.permissions.microphone.isUsable
        return CaptureIntent(wantsPreview: wantsPreview, wantsMicrophoneMonitor: wantsMic)
    }

    /// Applies the decision, only touching what has to change.
    @discardableResult
    public func callAsFunction(demand: CaptureDemand,
                               plan: @autoclosure () -> RecordingPlan?,
                               monitoringMicrophone: Bool,
                               deviceID: String?) async -> CaptureIntent {
        let intent = Self.intent(for: demand)
        if demand.recordingActive { return intent }

        if intent.wantsPreview, let plan = plan() {
            try? await engine.startPreview(plan)
        } else if !intent.wantsPreview, engine.isPreviewing {
            await engine.stopPreview()
        }

        if intent.wantsMicrophoneMonitor, !monitoringMicrophone {
            await microphone.start(deviceID: deviceID)
        } else if !intent.wantsMicrophoneMonitor, monitoringMicrophone {
            await microphone.stop()
        }
        return intent
    }
}
