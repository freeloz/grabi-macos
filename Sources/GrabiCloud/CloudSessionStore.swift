import Foundation
import Security

/// The Grabi Cloud session lives in the Keychain — never in UserDefaults,
/// never in a file. One generic-password item, JSON payload.
struct CloudSessionStore: Sendable {
    private static let service = "net.grabi.cloud"
    private static let account = "session"

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
            kSecAttrAccount as String: Self.account,
        ]
    }
}
