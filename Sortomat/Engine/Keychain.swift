import Foundation
import Security

/// The model API key, stored in the login Keychain (device-only, never synced).
/// A `SORTOMAT_API_KEY` (or legacy `MISTRAL_API_KEY`) environment variable
/// overrides it for headless/launchd runs and tests.
enum Keychain {
    private static let service = "ch.lkmc.Sortomat"
    static let apiKeyAccount = "model-api-key"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var attributes = base
        attributes[kSecValueData as String] = Data(value.utf8)
        // Device-only: the key must not roam to other Macs via iCloud Keychain.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func apiKey() -> String? {
        let env = ProcessInfo.processInfo.environment
        for name in ["SORTOMAT_API_KEY", "MISTRAL_API_KEY"] {
            if let value = env[name], !value.isEmpty { return value }
        }
        return get(apiKeyAccount)
    }
}
