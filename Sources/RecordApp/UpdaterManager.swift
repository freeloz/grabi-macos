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
///
/// Updater events are appended to ~/Library/Logs/Grabi/updater.log — one
/// short line each, no personal data — so beta reports about updates are
/// debuggable ("Report a problem" tells users where it is).
@MainActor
final class UpdaterManager: NSObject, ObservableObject {
    static let shared = UpdaterManager()

    /// nil when running outside a .app bundle (swift run / --screenshots):
    /// Sparkle needs a real bundle to locate and replace the app.
    private var controller: SPUStandardUpdaterController?
    @Published private(set) var canCheck = false
    private var cancellable: AnyCancellable?

    private override init() {
        super.init()
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheck = $0 }
        log("started v\(appVersion) feed=\(controller.updater.feedURL?.absoluteString ?? "?") auto=\(controller.updater.automaticallyChecksForUpdates)")
    }

    var isAvailable: Bool { controller != nil }

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    // MARK: - Event log (short lines, no personal data)

    nonisolated private func log(_ message: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Grabi")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("updater.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? line.write(to: file, atomically: true, encoding: .utf8)
        }
    }
}

extension UpdaterManager: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        log("appcast loaded: \(appcast.items.count) item(s)")
    }
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        log("update found: \(item.displayVersionString) (build \(item.versionString))")
    }
    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        log("no update (already current)")
    }
    nonisolated func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        log("download failed: \((error as NSError).localizedDescription)")
    }
    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let e = error as NSError
        guard e.domain != "SUSparkleErrorDomain" || e.code != 1001 else { return } // "no update" flows end here too
        log("aborted: [\(e.domain) \(e.code)] \(e.localizedDescription)")
    }
    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        log("installing \(item.displayVersionString)")
    }
}
