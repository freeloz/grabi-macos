import Foundation

/// Lookup of the engine's localized strings (the target's Bundle.module).
func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
}
