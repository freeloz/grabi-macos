import XCTest
@testable import GrabiDomain
@testable import GrabiUseCases

/// The rule this suite protects: nothing is shared without a session, and
/// the link the adapter returns reaches the caller untouched.
final class ShareToCloudUseCaseTests: XCTestCase {
    private final class FakeCloud: CloudPort, @unchecked Sendable {
        var storedAccount: CloudAccount?
        var sharedTitle: String?
        var result = CloudUpload(
            slug: "abc123XYZ",
            watchURL: URL(string: "https://app.grabi.net/w/abc123XYZ")!,
            expiresAt: nil
        )

        func account() async -> CloudAccount? { storedAccount }
        func signIn(email: String, password: String) async throws -> CloudAccount {
            CloudAccount(email: email, plan: "free")
        }
        func signUp(email: String, password: String, locale: String) async throws -> Bool { true }
        func signOut() async { storedAccount = nil }
        func googleAuthorizeURL() -> URL { URL(string: "https://example.test/authorize")! }
        func emailSignInURL() -> URL { URL(string: "https://example.test/login")! }
        func adoptSession(accessToken: String, refreshToken: String,
                          expiresIn: Double) async throws -> CloudAccount {
            let account = CloudAccount(email: "google@grabi.net", plan: "free")
            storedAccount = account
            return account
        }
        func share(_ recording: Recording, title: String,
                   onStage: @escaping @Sendable (CloudShareStage) -> Void) async throws -> CloudUpload {
            sharedTitle = title
            onStage(.exporting(0.5))
            onStage(.uploading(0.5))
            onStage(.finishing)
            return result
        }
    }

    private let recording = Recording(
        id: URL(fileURLWithPath: "/tmp/Grabi 2026-08-26.mov"),
        name: "Grabi 2026-08-26",
        date: Date(timeIntervalSince1970: 1_700_000_000),
        sizeBytes: 1_000_000
    )

    func testSharingWithoutSessionThrowsNotSignedIn() async {
        let cloud = FakeCloud()
        let share = ShareToCloudUseCase(cloud: cloud)
        do {
            _ = try await share(recording)
            XCTFail("expected notSignedIn")
        } catch let error as CloudError {
            XCTAssertEqual(error, .notSignedIn)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertNil(cloud.sharedTitle, "nothing must reach the adapter without a session")
    }

    func testSharingUsesTheRecordingNameAsDefaultTitle() async throws {
        let cloud = FakeCloud()
        cloud.storedAccount = CloudAccount(email: "e2e@grabi.net", plan: "free")
        let share = ShareToCloudUseCase(cloud: cloud)
        let upload = try await share(recording)
        XCTAssertEqual(cloud.sharedTitle, "Grabi 2026-08-26")
        XCTAssertEqual(upload.watchURL.absoluteString, "https://app.grabi.net/w/abc123XYZ")
    }

    func testAnExplicitTitleWinsOverTheDefault() async throws {
        let cloud = FakeCloud()
        cloud.storedAccount = CloudAccount(email: "e2e@grabi.net", plan: "free")
        let share = ShareToCloudUseCase(cloud: cloud)
        _ = try await share(recording, title: "Exposición de Química")
        XCTAssertEqual(cloud.sharedTitle, "Exposición de Química")
    }

    func testAnEmptyTitleFallsBackToTheDefault() async throws {
        let cloud = FakeCloud()
        cloud.storedAccount = CloudAccount(email: "e2e@grabi.net", plan: "free")
        let share = ShareToCloudUseCase(cloud: cloud)
        _ = try await share(recording, title: "")
        XCTAssertEqual(cloud.sharedTitle, "Grabi 2026-08-26")
    }

    func testStageCallbacksAreRelayed() async throws {
        let cloud = FakeCloud()
        cloud.storedAccount = CloudAccount(email: "e2e@grabi.net", plan: "free")
        let share = ShareToCloudUseCase(cloud: cloud)
        let box = StageBox()
        _ = try await share(recording) { stage in box.append(stage) }
        XCTAssertEqual(box.stages, [.exporting(0.5), .uploading(0.5), .finishing])
    }
}

/// Collects stages across the Sendable boundary without data races.
private final class StageBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _stages: [CloudShareStage] = []
    var stages: [CloudShareStage] { lock.withLock { _stages } }
    func append(_ stage: CloudShareStage) { lock.withLock { _stages.append(stage) } }
}
