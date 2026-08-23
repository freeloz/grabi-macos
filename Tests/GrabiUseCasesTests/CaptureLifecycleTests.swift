import XCTest
@testable import GrabiDomain
@testable import GrabiUseCases

/// The rule this suite protects: nothing captures unless someone is looking,
/// and a recording always wins. This is what keeps the camera light honest.
final class CaptureIntentTests: XCTestCase {
    private func demand(previewVisible: Bool = false,
                        panelOpen: Bool = false,
                        recordingActive: Bool = false,
                        sources: SourceSelection = SourceSelection(),
                        permissions: PermissionReport = .allAvailable) -> CaptureDemand {
        CaptureDemand(previewVisible: previewVisible, panelOpen: panelOpen,
                      recordingActive: recordingActive, sources: sources, permissions: permissions)
    }

    func testNothingRunsWhenNobodyIsLooking() {
        let intent = SyncCaptureUseCase.intent(for: demand())
        XCTAssertEqual(intent, .idle)
    }

    func testPreviewRunsWhileTheRecordSurfaceIsVisible() {
        let intent = SyncCaptureUseCase.intent(for: demand(previewVisible: true))
        XCTAssertTrue(intent.wantsPreview)
        XCTAssertTrue(intent.wantsMicrophoneMonitor)
    }

    func testLeavingTheRecordSurfaceReleasesEverything() {
        // This is the reported bug: switching to Recordings or Settings kept
        // the camera and the microphone alive.
        let intent = SyncCaptureUseCase.intent(for: demand(previewVisible: false))
        XCTAssertFalse(intent.wantsPreview)
        XCTAssertFalse(intent.wantsMicrophoneMonitor)
    }

    func testTheMenuBarPanelStillGetsItsLevelMeterWithoutAPreview() {
        let intent = SyncCaptureUseCase.intent(for: demand(panelOpen: true))
        XCTAssertFalse(intent.wantsPreview, "the panel shows no video")
        XCTAssertTrue(intent.wantsMicrophoneMonitor)
    }

    func testARecordingIsNeverInterrupted() {
        let intent = SyncCaptureUseCase.intent(for: demand(previewVisible: false, recordingActive: true))
        XCTAssertEqual(intent, .idle, "the engine owns the devices; the lifecycle must not touch them")
    }

    func testNoPreviewWithoutAVideoSource() {
        let voiceOnly = SourceSelection(screen: false, camera: false, microphone: true, systemAudio: false)
        let intent = SyncCaptureUseCase.intent(for: demand(previewVisible: true, sources: voiceOnly))
        XCTAssertFalse(intent.wantsPreview)
        XCTAssertTrue(intent.wantsMicrophoneMonitor)
    }

    func testADeniedMicrophoneIsNotMonitored() {
        let denied = PermissionReport(screen: .available, camera: .available,
                                      microphone: .permissionDenied, systemAudio: .available)
        let intent = SyncCaptureUseCase.intent(for: demand(previewVisible: true, permissions: denied))
        XCTAssertFalse(intent.wantsMicrophoneMonitor)
    }

    func testADeniedScreenDoesNotStartAScreenPreview() {
        let denied = PermissionReport(screen: .permissionDenied, camera: .available,
                                      microphone: .available, systemAudio: .available)
        let intent = SyncCaptureUseCase.intent(for: demand(previewVisible: true, permissions: denied))
        XCTAssertFalse(intent.wantsPreview)
    }
}

final class SyncCaptureUseCaseTests: XCTestCase {
    func testApplyingTheIntentStartsAndStopsThroughThePorts() async {
        let engine = FakeEngine()
        let mic = FakeMicrophoneMonitor()
        let sync = SyncCaptureUseCase(engine: engine, microphone: mic)
        let plan = RecordingPlan.preview(sources: SourceSelection(), target: .mainDisplay,
                                         devices: DeviceSelection(), cameraLayout: .default,
                                         quality: .standard)
        let visible = CaptureDemand(previewVisible: true, panelOpen: false, recordingActive: false,
                                    sources: SourceSelection(), permissions: .allAvailable)
        await sync(demand: visible, plan: plan, monitoringMicrophone: false, deviceID: "mic-7")
        XCTAssertEqual(engine.previewPlans.count, 1)
        XCTAssertEqual(mic.starts, ["mic-7"], "the chosen microphone is the one monitored")

        let hidden = CaptureDemand(previewVisible: false, panelOpen: false, recordingActive: false,
                                   sources: SourceSelection(), permissions: .allAvailable)
        await sync(demand: hidden, plan: plan, monitoringMicrophone: true, deviceID: "mic-7")
        XCTAssertEqual(engine.stopPreviewCalls, 1)
        XCTAssertEqual(mic.stops, 1)
    }

    func testNothingIsTouchedWhileRecording() async {
        let engine = FakeEngine()
        engine.state = .recording
        engine.isPreviewing = true
        let mic = FakeMicrophoneMonitor()
        let sync = SyncCaptureUseCase(engine: engine, microphone: mic)
        let recording = CaptureDemand(previewVisible: false, panelOpen: false, recordingActive: true,
                                      sources: SourceSelection(), permissions: .allAvailable)
        await sync(demand: recording, plan: nil, monitoringMicrophone: true, deviceID: nil)
        XCTAssertEqual(engine.stopPreviewCalls, 0)
        XCTAssertEqual(mic.stops, 0)
    }
}
