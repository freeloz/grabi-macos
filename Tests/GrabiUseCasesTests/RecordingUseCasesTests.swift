import XCTest
@testable import GrabiDomain
@testable import GrabiUseCases

final class EvaluateRecordabilityTests: XCTestCase {
    private let evaluate = EvaluateRecordability()

    func testNoSourcesIsItsOwnAnswer() {
        let none = SourceSelection(screen: false, camera: false, microphone: false, systemAudio: false)
        XCTAssertEqual(evaluate(sources: none, permissions: .allAvailable), .noSources)
    }

    func testBlockedSourcesAreNamed() {
        let denied = PermissionReport(screen: .available, camera: .permissionDenied,
                                      microphone: .available, systemAudio: .available)
        XCTAssertEqual(evaluate(sources: SourceSelection(), permissions: denied), .blocked([.camera]))
    }

    func testReadyWhenEverythingRequestedIsUsable() {
        let screenOnly = SourceSelection(screen: true, camera: false, microphone: false, systemAudio: false)
        let denied = PermissionReport(screen: .available, camera: .permissionDenied,
                                      microphone: .permissionDenied, systemAudio: .available)
        XCTAssertEqual(evaluate(sources: screenOnly, permissions: denied), .ready)
    }
}

final class StartRecordingUseCaseTests: XCTestCase {
    private let folder = URL(fileURLWithPath: "/tmp/GrabiTests")
    private let clock = FixedClock(date: Date(timeIntervalSince1970: 1_756_000_000))

    private func request(_ sources: SourceSelection = SourceSelection(),
                         quality: RecordingQuality = .standard) -> StartRecordingUseCase.Request {
        .init(sources: sources, target: .mainDisplay, devices: DeviceSelection(cameraID: "cam-9"),
              cameraLayout: .default, quality: quality, destinationFolder: folder)
    }

    func testStartsWithAFullQualityPlanInTheDestinationFolder() async throws {
        let engine = FakeEngine()
        let start = StartRecordingUseCase(engine: engine, permissions: FakePermissions(), clock: clock)
        let blocked = try await start(request(quality: .sharp))
        XCTAssertTrue(blocked.isEmpty)
        let plan = try XCTUnwrap(engine.recordingPlans.first)
        XCTAssertEqual(plan.targetWidth, 3840, "recording must not inherit the preview's cap")
        XCTAssertEqual(plan.framesPerSecond, 30)
        XCTAssertEqual(plan.devices.cameraID, "cam-9", "the chosen camera has to reach the engine")
        XCTAssertEqual(plan.outputURL?.deletingLastPathComponent().path, folder.path)
    }

    func testAsksForAccessBeforeRecording() async throws {
        let permissions = FakePermissions()
        let start = StartRecordingUseCase(engine: FakeEngine(), permissions: permissions, clock: clock)
        _ = try await start(request())
        XCTAssertEqual(permissions.calls.requestedAccess, [true])
    }

    func testReportsBlockedSourcesInsteadOfRecordingHalfOfThem() async throws {
        var permissions = FakePermissions()
        permissions.reportToReturn = PermissionReport(screen: .available, camera: .permissionDenied,
                                                      microphone: .available, systemAudio: .available)
        let engine = FakeEngine()
        let start = StartRecordingUseCase(engine: engine, permissions: permissions, clock: clock)
        let blocked = try await start(request())
        XCTAssertEqual(blocked, [.camera])
        XCTAssertTrue(engine.recordingPlans.isEmpty, "nothing may start until the user decides")
    }

    func testRefusesWithoutSources() async {
        let none = SourceSelection(screen: false, camera: false, microphone: false, systemAudio: false)
        let start = StartRecordingUseCase(engine: FakeEngine(), permissions: FakePermissions(), clock: clock)
        do {
            _ = try await start(request(none))
            XCTFail("expected noActiveSources")
        } catch {
            XCTAssertEqual(error as? GrabiError, .noActiveSources)
        }
    }

    func testRefusesToStartTwice() async {
        let engine = FakeEngine()
        engine.state = .recording
        let start = StartRecordingUseCase(engine: engine, permissions: FakePermissions(), clock: clock)
        do {
            _ = try await start(request())
            XCTFail("expected alreadyRecording")
        } catch {
            XCTAssertEqual(error as? GrabiError, .alreadyRecording)
        }
    }
}

final class StopRecordingUseCaseTests: XCTestCase {
    func testStoppingReleasesTheCaptureAndNotifies() async throws {
        // The reported bug: after stop the pipeline stayed alive for the
        // preview, so the camera light stayed on and macOS kept saying
        // "Currently Sharing".
        let engine = FakeEngine()
        engine.state = .recording
        engine.isPreviewing = true
        let notifier = FakeNotifier()
        let stop = StopRecordingUseCase(engine: engine, notifier: notifier)

        let url = try await stop(elapsed: 42)

        XCTAssertEqual(url, engine.stopResult)
        XCTAssertEqual(engine.stopPreviewCalls, 1, "the capture must be released on stop")
        XCTAssertFalse(engine.isPreviewing)
        XCTAssertEqual(notifier.finished.count, 1)
        XCTAssertEqual(notifier.finished.first?.1, 42)
    }

    func testStoppingWhenIdleIsAnError() async {
        let stop = StopRecordingUseCase(engine: FakeEngine(), notifier: FakeNotifier())
        do {
            _ = try await stop(elapsed: 0)
            XCTFail("expected notRecording")
        } catch {
            XCTAssertEqual(error as? GrabiError, .notRecording)
        }
    }
}

final class TogglePauseUseCaseTests: XCTestCase {
    func testPausesWhileRecordingAndResumesWhilePaused() {
        let engine = FakeEngine()
        let toggle = TogglePauseUseCase(engine: engine)

        engine.state = .recording
        toggle()
        XCTAssertEqual(engine.pauseCalls, 1)

        toggle()
        XCTAssertEqual(engine.resumeCalls, 1)
    }

    func testDoesNothingWhenIdle() {
        let engine = FakeEngine()
        TogglePauseUseCase(engine: engine)()
        XCTAssertEqual(engine.pauseCalls, 0)
        XCTAssertEqual(engine.resumeCalls, 0)
    }
}
