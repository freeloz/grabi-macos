import Foundation

/// The language Grabi speaks. `.system` follows the Mac; the rest override it
/// so a user can read Grabi in one language while the system is in another
/// (common on shared or work machines).
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, en, es, pt, fr, de

    public var id: String { rawValue }

    /// Name written in its own language — how language pickers should read.
    public var displayName: String {
        switch self {
        case .system: return L("lang.system")
        case .en: return "English"
        case .es: return "Español"
        case .pt: return "Português"
        case .fr: return "Français"
        case .de: return "Deutsch"
        }
    }
}

/// Resolves which localization bundle every module should read from.
///
/// Each target keeps its own `Localizable.strings`, so switching language at
/// runtime means resolving each target's `.lproj` sub-bundle instead of
/// relying on the process-wide language (which only changes on relaunch).
public enum GrabiLocale {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var selected: AppLanguage = .system
    nonisolated(unsafe) private static var cache: [String: Bundle] = [:]

    public static var current: AppLanguage {
        lock.lock(); defer { lock.unlock() }
        return selected
    }

    /// Changing the language empties the resolved-bundle cache; views re-read
    /// their strings on the next render.
    public static func set(_ language: AppLanguage) {
        lock.lock()
        selected = language
        cache.removeAll()
        lock.unlock()
    }

    /// The bundle a module should read its strings from, honoring the
    /// override. Falls back to the module itself when the language has no
    /// catalog (then macOS applies its own resolution).
    public static func bundle(for module: Bundle) -> Bundle {
        lock.lock(); defer { lock.unlock() }
        guard selected != .system else { return module }
        let key = "\(module.bundlePath)#\(selected.rawValue)"
        if let cached = cache[key] { return cached }
        guard let path = module.path(forResource: selected.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return module }
        cache[key] = bundle
        return bundle
    }
}
