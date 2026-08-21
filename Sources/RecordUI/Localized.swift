import Foundation

/// Strings localizados de los componentes (Bundle.module del target).
func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
}
