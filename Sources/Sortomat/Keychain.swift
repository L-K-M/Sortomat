import Foundation
import Security

enum Keychain {
    private static let service = "ch.lmathis.sortomat"
    static let apiKeyAccount = "mistral-api-key"

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
        SecItemAdd(attributes as CFDictionary, nil)
    }

    /// API key from Keychain, with an environment-variable override for
    /// headless use (launchd jobs, tests).
    static func apiKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["MISTRAL_API_KEY"],
           !env.isEmpty {
            return env
        }
        return get(apiKeyAccount)
    }
}
