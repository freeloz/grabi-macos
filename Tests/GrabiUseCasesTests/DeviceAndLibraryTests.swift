import XCTest
@testable import GrabiDomain
@testable import GrabiUseCases

final class RefreshDevicesUseCaseTests: XCTestCase {
    private let camera = CaptureDeviceInfo(id: "cam-1", name: "FaceTime HD", isSystemDefault: true)
    private let usbMic = CaptureDeviceInfo(id: "mic-usb", name: "Yeti", isSystemDefault: false)

    func testKeepsAChoiceThatIsStillConnected() {
        let directory = FakeDeviceDirectory(camerasToReturn: [camera], microphonesToReturn: [usbMic])
        let refresh = RefreshDevicesUseCase(directory: directory)
        let result = refresh(current: DeviceSelection(cameraID: "cam-1", microphoneID: "mic-usb"))
        XCTAssertEqual(result.selection.cameraID, "cam-1")
        XCTAssertEqual(result.selection.microphoneID, "mic-usb")
        XCTAssertFalse(result.cameraChanged)
        XCTAssertFalse(result.microphoneChanged)
    }

    func testFallsBackWhenTheChosenDeviceIsGone() {
        let directory = FakeDeviceDirectory(camerasToReturn: [camera], microphonesToReturn: [])
        let refresh = RefreshDevicesUseCase(directory: directory)
        let result = refresh(current: DeviceSelection(cameraID: "unplugged", microphoneID: "mic-usb"))
        XCTAssertNil(result.selection.cameraID)
        XCTAssertNil(result.selection.microphoneID)
        XCTAssertTrue(result.cameraChanged)
        XCTAssertTrue(result.microphoneChanged)
    }

    func testReportsWhatIsConnected() {
        let directory = FakeDeviceDirectory(camerasToReturn: [camera], microphonesToReturn: [usbMic])
        let result = RefreshDevicesUseCase(directory: directory)(current: DeviceSelection())
        XCTAssertEqual(result.cameras.map(\.name), ["FaceTime HD"])
        XCTAssertEqual(result.microphones.map(\.name), ["Yeti"])
    }
}

final class ChangeLanguageUseCaseTests: XCTestCase {
    func testRemembersAndAppliesTheLanguage() {
        let preferences = FakePreferences()
        let localization = FakeLocalization()
        let change = ChangeLanguageUseCase(localization: localization, preferences: preferences)
        change(.pt)
        XCTAssertEqual(preferences.language, .pt, "the choice has to survive a relaunch")
        XCTAssertEqual(localization.applied, [.pt], "and apply right away, without one")
    }
}

final class LibraryUseCasesTests: XCTestCase {
    private func recording(_ name: String, daysAgo: Int, bytes: Int64) -> Recording {
        Recording(id: URL(fileURLWithPath: "/tmp/\(name).mov"),
                  name: name,
                  date: Date(timeIntervalSince1970: 1_756_000_000 - Double(daysAgo) * 86_400),
                  sizeBytes: bytes)
    }

    func testNewestFirst() {
        let library = FakeLibrary()
        library.stored = [recording("old", daysAgo: 5, bytes: 100),
                          recording("newest", daysAgo: 0, bytes: 200),
                          recording("middle", daysAgo: 2, bytes: 300)]
        let list = ListRecordingsUseCase(library: library)
        XCTAssertEqual(list(in: URL(fileURLWithPath: "/tmp")).map(\.name),
                       ["newest", "middle", "old"])
    }

    func testTotalBytesAddsUp() {
        let library = FakeLibrary()
        let list = ListRecordingsUseCase(library: library)
        let items = [recording("a", daysAgo: 0, bytes: 1000), recording("b", daysAgo: 1, bytes: 2500)]
        XCTAssertEqual(list.totalBytes(items), 3500)
    }

    func testDeletingMovesToTrashSoItCanComeBack() throws {
        let library = FakeLibrary()
        let item = recording("clip", daysAgo: 0, bytes: 10)
        library.stored = [item]
        try DeleteRecordingUseCase(library: library)(item)
        XCTAssertEqual(library.trashed.map(\.name), ["clip"])
        XCTAssertTrue(library.stored.isEmpty)
    }
}
