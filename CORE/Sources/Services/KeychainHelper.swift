import Foundation
import Security

/// Minimal Keychain wrapper for third-party API keys. Never store API keys
/// in UserDefaults or source control.
enum KeychainHelper {
    private static let account = "api-key"
    private static let tripoService  = "app.core.tripo"
    private static let claudeService = "app.core.claude"

    // MARK: Tripo

    static func saveTripoKey(_ key: String) { save(key, service: tripoService) }
    static func tripoKey() -> String? { read(service: tripoService) }

    // MARK: Claude

    static func saveClaudeKey(_ key: String) { save(key, service: claudeService) }
    static func claudeKey() -> String? { read(service: claudeService) }

    // MARK: Generic

    /// Saving an empty string deletes the entry.
    static func save(_ key: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !key.isEmpty else { return }
        var insert = query
        insert[kSecValueData as String] = Data(key.utf8)
        SecItemAdd(insert as CFDictionary, nil)
    }

    static func read(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else { return nil }
        return key
    }
}
