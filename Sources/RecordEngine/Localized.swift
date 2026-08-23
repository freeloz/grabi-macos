import Foundation

/// Lookup of the engine's localized strings, honoring the in-app language.
func L(_ key: String) -> String {
    GrabiLocale.bundle(for: .module).localizedString(forKey: key, value: nil, table: nil)
}
