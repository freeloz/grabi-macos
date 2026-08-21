import Foundation
import Combine
import Sparkle

/// One shared Sparkle updater for the whole app.
///
/// The automatic behavior lives in Info.plist (SUEnableAutomaticChecks +
/// SUScheduledCheckInterval = once a day, quietly); this wrapper only adds
/// the manual "check now" entry point and the bits Settings displays.
/// Sparkle's own update dialogs are native and ship localized in all of
/// Grabi's languages; the release notes they show come from our appcast.
@MainActor
final class UpdaterManager: ObservableObject {
    static let shared = UpdaterManager()

    /// nil when running outside a .app bundle (swift run / --screenshots):
    /// Sparkle needs a real bundle to locate and replace the app.
    private let controller: SPUStandardUpdaterController?
    @Published private(set) var canCheck = false
    private var cancellable: AnyCancellable?

    private init() {
        guard Bundle.main.bundlePath.hasSuffix(".app") else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheck = $0 }
    }

    var isAvailable: Bool { controller != nil }

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
