import Foundation

/// Strings localizados de la app (Bundle.module del target).
func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
}

func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}
