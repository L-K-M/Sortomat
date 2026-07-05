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

    /// Store (or clear, for an empty value) the item. Updates in place rather
    /// than delete-then-add: the old delete-first approach destroyed the stored
    /// key even when the subsequent add failed, and ignored both statuses while
    /// the UI reported "Saved". Returns whether the keychain accepted the write.
    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        guard !value.isEmpty else {
            let status = SecItemDelete(base as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }

        // Device-only: the key must not roam to other Macs via iCloud Keychain.
        let payload: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(base as CFDictionary, payload as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var attributes = base
        payload.forEach { attributes[$0.key] = $0.value }
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func apiKey() -> String? {
        let env = ProcessInfo.processInfo.environment
        for name in ["SORTOMAT_API_KEY", "MISTRAL_API_KEY"] {
            if let value = env[name], !value.isEmpty { return value }
        }
        return get(apiKeyAccount)
    }
}
