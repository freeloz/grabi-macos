import Foundation

/// Búsqueda de strings localizados del motor (Bundle.module del target).
func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
}
