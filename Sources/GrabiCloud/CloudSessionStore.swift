import Foundation
import Security

/// The Grabi Cloud session lives in the Keychain — never in UserDefaults,
/// never in a file. One generic-password item, JSON payload.
struct CloudSessionStore: Sendable {
    private static let service = "net.grabi.cloud"
    /// Un slot por ambiente. Las dos apps van firmadas por el mismo equipo y
    /// ven el mismo llavero: con un solo slot, entrar en staging dejaba
    /// tokens de staging que la app de producción cargaba, no validaba y
    /// borraba — deslogueando a las dos (31 ago 2026).
    private static var defaultAccount: String {
        Bundle.main.bundleIdentifier?.hasSuffix(".staging") == true ? "session.staging" : "session"
    }
    private let account: String

    init(account: String = CloudSessionStore.defaultAccount) { self.account = account }

    func load() -> CloudTokens? {
        var query = base()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(CloudTokens.self, from: data)
    }

    func save(_ tokens: CloudTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        var query = base()
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    func clear() {
        SecItemDelete(base() as CFDictionary)
    }

    private func base() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
    }
}
