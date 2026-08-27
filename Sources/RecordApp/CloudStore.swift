import AppKit
import Foundation
import GrabiDomain
import GrabiUseCases

/// Observable state for Grabi Cloud: the session and the per-recording
/// share progress the library cards render. The flow the product is built
/// around: share → link lands on the pasteboard → paste anywhere.
@MainActor
final class CloudStore: ObservableObject {
    enum ShareState: Equatable {
        case working(CloudShareStage)
        case done(CloudUpload)
        case failed(CloudError)
    }

    @Published private(set) var account: CloudAccount?
    @Published private(set) var accountLoaded = false
    @Published private(set) var shares: [URL: ShareState] = [:]

    private let cloud: CloudPort
    private let share: ShareToCloudUseCase

    init(cloud: CloudPort, share: ShareToCloudUseCase) {
        self.cloud = cloud
        self.share = share
    }

    func refreshAccount() {
        Task {
            account = await cloud.account()
            accountLoaded = true
        }
    }

    func signIn(email: String, password: String) async throws {
        account = try await cloud.signIn(email: email, password: password)
    }

    /// true = sesión iniciada; false = falta confirmar el correo.
    func signUp(email: String, password: String) async throws -> Bool {
        let signedIn = try await cloud.signUp(
            email: email, password: password,
            locale: GrabiLocaleCode.current
        )
        if signedIn { account = await cloud.account() }
        return signedIn
    }

    func signOut() {
        Task {
            await cloud.signOut()
            account = nil
        }
    }

    func share(_ item: RecordingItem) {
        guard shares[item.id]?.isWorking != true else { return }
        let recording = Recording(id: item.id, name: item.name, date: item.date,
                                  sizeBytes: item.sizeBytes, duration: item.duration)
        shares[item.id] = .working(.exporting(0))
        let useCase = self.share // la use case (propiedad), no este método
        let box = WeakStoreBox(self) // capturable en closures @Sendable sin quejas
        Task { [weak self] in
            var outcome: ShareState
            do {
                let upload = try await useCase(recording) { stage in
                    Task { @MainActor in
                        box.store?.shares[recording.id] = .working(stage)
                    }
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(upload.watchURL.absoluteString, forType: .string)
                outcome = .done(upload)
            } catch let error as CloudError {
                outcome = .failed(error)
            } catch {
                outcome = .failed(.network(error.localizedDescription))
            }
            guard let self else { return }
            self.shares[recording.id] = outcome
            if case .done = outcome {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if case .done = self.shares[recording.id] { self.shares[recording.id] = nil }
            }
        }
    }

    func dismissFailure(_ item: RecordingItem) {
        if case .failed = shares[item.id] { shares[item.id] = nil }
    }
}

/// Referencia débil empaquetada como constante Sendable: los closures
/// @Sendable pueden capturarla sin el error "captured var" de Swift 6.
private final class WeakStoreBox: @unchecked Sendable {
    weak var store: CloudStore?
    init(_ store: CloudStore) { self.store = store }
}

extension CloudStore.ShareState {
    var isWorking: Bool { if case .working = self { return true }; return false }
}

/// The app language as a Grabi Cloud locale code.
enum GrabiLocaleCode {
    static var current: String {
        let code = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "en"
        return ["es", "en", "pt", "fr", "de"].contains(code) ? String(code) : "en"
    }
}

/// Human words for everything cloud that can go wrong or be in progress.
extension CloudError {
    var userMessage: String {
        switch self {
        case .notSignedIn: return L("app.cloud.signInFirst")
        case .badCredentials: return L("app.cloud.badCredentials")
        case .emailNotConfirmed: return L("app.cloud.checkEmail")
        case .planLimit("duration"): return L("app.cloud.limit.duration")
        case .planLimit("count"): return L("app.cloud.limit.count")
        case .planLimit: return L("app.cloud.limit.storage")
        case .exportFailed: return L("app.cloud.exportFailed")
        case .network: return L("app.cloud.failed")
        }
    }
}
