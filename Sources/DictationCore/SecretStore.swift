import Foundation
import Security

/// Stores API keys. Never logs values. UserDefaults is not used for secrets.
public protocol SecretStore: Sendable {
    func secret(for account: String) -> String?
    /// Presence only. Must not show Keychain or SecurityAgent UI.
    func containsSecret(for account: String) -> Bool
    func setSecret(_ value: String?, for account: String) throws
}

/// Keychain lookup that never presents an unlock sheet.
public enum KeychainPresence {
    public static func query(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
        ]
    }

    /// Locked items still count as present so status checks do not prompt.
    public static func itemExists(status: OSStatus) -> Bool {
        switch status {
        case errSecSuccess, errSecInteractionNotAllowed, errSecAuthFailed:
            return true
        default:
            return false
        }
    }
}

public struct KeychainSecretStore: SecretStore, Sendable {
    public static let apiKeyAccount = "openai-compatible-api-key"
    public static let chatAPIKeyAccount = "openai-compatible-chat-api-key"

    private let service: String

    public init(service: String = "com.vishesh.codex-dictation") {
        self.service = service
    }

    public func containsSecret(for account: String) -> Bool {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(KeychainPresence.query(service: service, account: account) as CFDictionary,
                                         &item)
        return KeychainPresence.itemExists(status: status)
    }

    public func secret(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setSecret(_ value: String?, for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw DictationError.invalidCredentials }
    }
}

public final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private var values: [String: String] = [:]
    private let lock = NSLock()

    public init(_ initial: [String: String] = [:]) {
        values = initial
    }

    public func secret(for account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[account]
    }

    public func containsSecret(for account: String) -> Bool {
        secret(for: account) != nil
    }

    public func setSecret(_ value: String?, for account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if let value, !value.isEmpty {
            values[account] = value
        } else {
            values.removeValue(forKey: account)
        }
    }
}
