import Foundation
import Security

/// Stores server access tokens in the keychain, keyed by server id.
struct KeychainStore: Sendable {
    private let service: String

    init(service: String = AppIdentity.keychainService) {
        self.service = service
    }

    /// What reading a token found. `unavailable` is the keychain refusing for now
    /// (say, before the device's first unlock), not the token being gone.
    enum Lookup {
        case found(String)
        case missing
        case unavailable
    }

    func token(for account: String) -> String? {
        if case let .found(token) = lookUpToken(for: account) { token } else { nil }
    }

    func lookUpToken(for account: String) -> Lookup {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else { return .missing }
            return .found(token)
        case errSecItemNotFound:
            return .missing
        default:
            return .unavailable
        }
    }

    @discardableResult
    func setToken(_ token: String, for account: String) -> Bool {
        let data = Data(token.utf8)
        let query = baseQuery(account: account)
        let update = [kSecValueData as String: data] as CFDictionary
        let status = SecItemUpdate(query as CFDictionary, update)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    func removeToken(for account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
