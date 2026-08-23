import XCTest
@testable import GrabiDomain

final class SourceSelectionTests: XCTestCase {
    func testEmptySelectionHasNothingActive() {
        let none = SourceSelection(screen: false, camera: false, microphone: false, systemAudio: false)
        XCTAssertTrue(none.isEmpty)
        XCTAssertTrue(none.active.isEmpty)
        XCTAssertFalse(none.hasVideo)
    }

    func testAudioOnlySelectionHasNoVideo() {
        let voice = SourceSelection(screen: false, camera: false, microphone: true, systemAudio: false)
        XCTAssertFalse(voice.isEmpty)
        XCTAssertFalse(voice.hasVideo, "a microphone alone cannot feed a preview")
    }

    func testSubscriptReadsAndWritesEverySource() {
        var selection = SourceSelection(screen: false, camera: false, microphone: false, systemAudio: false)
        for source in RecordingSource.allCases {
            selection[source] = true
            XCTAssertTrue(selection[source], "\(source) should be on")
        }
        XCTAssertEqual(selection.active.count, RecordingSource.allCases.count)
    }
}

final class PermissionReportTests: XCTestCase {
    func testBlockedListsOnlyRequestedSources() {
        let report = PermissionReport(screen: .available,
                                      camera: .permissionDenied(help: "Allow it in System Settings"),
                                      microphone: .unavailable(reason: "no mic"),
                                      systemAudio: .available)
        let screenOnly = SourceSelection(screen: true, camera: false, microphone: false, systemAudio: false)
        XCTAssertTrue(report.blocked(in: screenOnly).isEmpty,
                      "a denied camera must not block a screen-only recording")

        let withCamera = SourceSelection(screen: true, camera: true, microphone: true, systemAudio: false)
        XCTAssertEqual(Set(report.blocked(in: withCamera)), Set<RecordingSource>([.camera, .microphone]))
    }
}

final class CameraLayoutTests: XCTestCase {
    func testClampKeepsTheFrameInsideTheCanvas() {
        let outside = CameraLayout(shape: .circle, origin: CGPoint(x: 1.4, y: -0.3), height: 0.3)
        let clamped = outside.clamped(canvasWidth: 1600, canvasHeight: 900)
        XCTAssertGreaterThanOrEqual(clamped.origin.x, 0)
        XCTAssertGreaterThanOrEqual(clamped.origin.y, 0)
        XCTAssertLessThanOrEqual(clamped.origin.y + clamped.height, 1.0001)
    }

    func testRectangleIsWiderThanTall() {
        XCTAssertEqual(CameraShape.rectangle.aspectRatio, 1.5)
        XCTAssertEqual(CameraShape.circle.aspectRatio, 1.0)
    }
}

final class DeviceSelectionTests: XCTestCase {
    private let builtIn = CaptureDeviceInfo(id: "cam-1", name: "FaceTime", isSystemDefault: true)
    private let mic = CaptureDeviceInfo(id: "mic-1", name: "Built-in", isSystemDefault: true)

    func testUnpluggedDeviceFallsBackToSystemDefault() {
        let chosen = DeviceSelection(cameraID: "usb-webcam", microphoneID: "mic-1")
        let reconciled = chosen.reconciled(cameras: [builtIn], microphones: [mic])
        XCTAssertNil(reconciled.cameraID, "a camera that is gone must fall back")
        XCTAssertEqual(reconciled.microphoneID, "mic-1", "a connected mic must be kept")
    }
}

final class RecordingPlanTests: XCTestCase {
    private func plan(_ quality: RecordingQuality, preview: Bool) -> RecordingPlan {
        let sources = SourceSelection()
        return preview
            ? .preview(sources: sources, target: .mainDisplay, devices: DeviceSelection(),
                       cameraLayout: .default, quality: quality)
            : .recording(sources: sources, target: .mainDisplay, devices: DeviceSelection(),
                         cameraLayout: .default, quality: quality,
                         outputURL: URL(fileURLWithPath: "/tmp/x.mov"))
    }

    func testPreviewIsCheaperThanRecording() {
        let preview = plan(.sharp, preview: true)
        let recording = plan(.sharp, preview: false)
        XCTAssertLessThan(preview.targetWidth, recording.targetWidth)
        XCTAssertLessThan(preview.framesPerSecond, recording.framesPerSecond)
        XCTAssertTrue(preview.isPreview)
        XCTAssertFalse(recording.isPreview)
    }

    func testPreviewNeverCapturesTheMicrophoneButKeepsSystemAudio() {
        let preview = plan(.standard, preview: true)
        XCTAssertFalse(preview.sources.microphone, "the monitor session owns the mic while framing")
        XCTAssertTrue(preview.sources.systemAudio, "its level meter has to show something real")
    }

    func testStandardQualityIsNotUpscaled() {
        XCTAssertEqual(plan(.standard, preview: false).targetWidth, 1920)
        XCTAssertEqual(plan(.sharp, preview: false).targetWidth, 3840)
    }

    func testFileNameIsTheSameInEveryLocale() {
        let date = Date(timeIntervalSince1970: 1_756_000_000)
        let name = RecordingNaming.fileName(for: date)
        XCTAssertTrue(name.hasPrefix("Grabi "))
        XCTAssertTrue(name.hasSuffix(".mov"))
        XCTAssertEqual(name.filter { $0 == "-" }.count, 2)
    }
}

final class RecordingStateTests: XCTestCase {
    func testActiveStatesOwnTheDevices() {
        for state in [RecordingState.starting, .recording, .paused, .stopping] {
            XCTAssertTrue(state.isActive, "\(state) must count as active")
        }
        for state in [RecordingState.idle, .stopped(URL(fileURLWithPath: "/tmp/a.mov")), .failed("x")] {
            XCTAssertFalse(state.isActive)
        }
    }
}
