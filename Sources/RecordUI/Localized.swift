import Foundation
import RecordEngine
import GrabiDomain

/// Localized strings for the components, honoring the in-app language.
func L(_ key: String) -> String {
    GrabiLocale.bundle(for: .module).localizedString(forKey: key, value: nil, table: nil)
}
