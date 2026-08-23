import Foundation
import RecordEngine

/// Localized strings for the app, honoring the in-app language.
func L(_ key: String) -> String {
    GrabiLocale.bundle(for: .module).localizedString(forKey: key, value: nil, table: nil)
}

func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}
