import Foundation
import Security
import SportsKit

/// The Anthropic API key, kept in the Keychain. Claude features show only while one is set.
@MainActor @Observable
final class ClaudeKey {
    static let shared = ClaudeKey()

    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.marcuscunningham.SportsApp.anthropic",
        kSecAttrAccount as String: "api-key",
    ]

    private(set) var value: String?

    var service: ClaudeService? { value.map { ClaudeService(apiKey: $0) } }

    private init() {
        var query = Self.query
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data {
            value = String(data: data, encoding: .utf8)
        }
    }

    /// Saves the key, or removes it when empty. Returns false if the Keychain refused.
    @discardableResult
    func set(_ key: String) -> Bool {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            SecItemDelete(Self.query as CFDictionary)
            value = nil
            return true
        }
        // Update in place, adding only when there's nothing saved yet, so a refused write never loses the old key.
        let data = [kSecValueData as String: Data(key.utf8)]
        var status = SecItemUpdate(Self.query as CFDictionary, data as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(Self.query.merging(data) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { return false }
        value = key
        return true
    }
}
