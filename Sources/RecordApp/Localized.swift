import Foundation

/// Localized strings for the app (the target's Bundle.module).
func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
}

func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}
