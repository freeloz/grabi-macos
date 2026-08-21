import Foundation

/// Localized strings for the components (the target's Bundle.module).
func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
}
