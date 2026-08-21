import Foundation
import AppKit

/// Every external link the app opens, in one place (mirror of the website's
/// src/config.ts). Optional links are nil until the account exists — UI that
/// uses them must simply not render, never point at a dead page.
enum AppLinks {
    static let website = URL(string: "https://grabi.net")!
    static let repo = URL(string: "https://github.com/freeloz/grabi-macos")!

    // TODO: fill in when the accounts are created (keep grabi-web's
    // src/config.ts in sync). nil = the UI hides the entry.
    static let coffee: URL? = nil        // Buy Me a Coffee
    static let sponsors: URL? = nil      // GitHub Sponsors
    static let youtube: URL? = nil
    static let twitter: URL? = nil
    static let mastodon: URL? = nil

    /// "Report a problem…" → GitHub issue form pre-filled with the
    /// environment data a non-technical user can't collect on their own.
    static func newIssue() -> URL {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let macos = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        var chip = "Intel"
        var isARM: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &isARM, &size, nil, 0) == 0, isARM == 1 {
            chip = "Apple Silicon"
        }
        let language = Locale.preferredLanguages.first ?? "?"

        var comps = URLComponents(url: repo.appendingPathComponent("issues/new"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "template", value: "bug_report.yml"),
            .init(name: "labels", value: "bug"),
            .init(name: "app-version", value: version),
            .init(name: "macos-version", value: macos),
            .init(name: "chip", value: chip),
            .init(name: "language", value: language),
        ]
        return comps.url!
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
