import Foundation
import Security

/// Stores API keys. Never logs values. UserDefaults is not used for secrets.
public protocol SecretStore: Sendable {
    func secret(for account: String) -> String?
    /// Presence only. Must not show Keychain or SecurityAgent UI.
    func containsSecret(for account: String) -> Bool
    func setSecret(_ value: String?, for account: String) throws
}

/// File-based items carry an app ACL (breaks after Developer ID resign).
/// Data Protection items use accessibility, not that ACL.
public enum KeychainItemFormat: Equatable, Sendable {
    case dataProtection
    case fileBased
}

/// Builds Keychain dictionaries. Tests assert UI and accessibility flags here.
public enum KeychainQueries {
    public static func identity(service: String, account: String,
                                format: KeychainItemFormat) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: format == .dataProtection
        ]
    }

    public static func presence(service: String, account: String,
                                format: KeychainItemFormat) -> [String: Any] {
        var query = identity(service: service, account: account, format: format)
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        return query
    }

    public static func read(service: String, account: String, format: KeychainItemFormat,
                            allowUI: Bool) -> [String: Any] {
        var query = identity(service: service, account: account, format: format)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if !allowUI {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        }
        return query
    }

    public static func add(service: String, account: String, data: Data,
                           format: KeychainItemFormat, access: SecAccess?) -> [String: Any] {
        var attributes = identity(service: service, account: account, format: format)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecAttrLabel as String] = "Goice API key"
        if format == .fileBased, let access {
            attributes[kSecAttrAccess as String] = access
        }
        return attributes
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

/// Compatibility name used by status tests.
public enum KeychainPresence {
    public static func query(service: String, account: String) -> [String: Any] {
        KeychainQueries.presence(service: service, account: account, format: .fileBased)
    }

    public static func itemExists(status: OSStatus) -> Bool {
        KeychainQueries.itemExists(status: status)
    }
}

public protocol KeychainRuntime: Sendable {
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?)
    func add(_ attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

public struct SecurityKeychainRuntime: KeychainRuntime {
    public init() {}

    public func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (status, item as? Data)
    }

    public func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    public func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainAccessFactory {
    /// Current process as a trusted app. Rewrites a stale CDHash ACL after resign.
    static func currentApplication(name: String) -> SecAccess? {
        var trusted: SecTrustedApplication?
        guard SecTrustedApplicationCreateFromPath(nil, &trusted) == errSecSuccess,
              let trusted else { return nil }
        var access: SecAccess?
        let trustedList = [trusted] as CFArray
        guard SecAccessCreate(name as CFString, trustedList, &access) == errSecSuccess else { return nil }
        return access
    }
}

/// Process-lifetime cache plus one unlock, then rewrite so this signed binary stays trusted.
public final class KeychainSecretStore: SecretStore, @unchecked Sendable {
    public static let apiKeyAccount = "openai-compatible-api-key"
    public static let chatAPIKeyAccount = "openai-compatible-chat-api-key"

    private let service: String
    private let runtime: KeychainRuntime
    private let lock = NSLock()
    private var cache: [String: String] = [:]

    public init(service: String = "com.vishesh.codex-dictation",
                runtime: KeychainRuntime = SecurityKeychainRuntime()) {
        self.service = service
        self.runtime = runtime
    }

    public func containsSecret(for account: String) -> Bool {
        if cachedValue(for: account) != nil { return true }
        return exists(account, format: .dataProtection) || exists(account, format: .fileBased)
    }

    public func secret(for account: String) -> String? {
        if let cached = cachedValue(for: account) { return cached }
        if let value = copySecret(account, format: .dataProtection, allowUI: true) {
            storeCache(value, for: account)
            return value
        }
        if let value = copySecret(account, format: .fileBased, allowUI: true) {
            storeCache(value, for: account)
            migrateStaleAccess(account, value: value)
            return value
        }
        return nil
    }

    public func setSecret(_ value: String?, for account: String) throws {
        deleteAllFormats(account)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else {
            storeCache(nil, for: account)
            return
        }
        let status = writeTrusted(account, data: data)
        guard status == errSecSuccess else { throw DictationError.invalidCredentials }
        storeCache(value, for: account)
    }

    // MARK: Private

    private func exists(_ account: String, format: KeychainItemFormat) -> Bool {
        let query = KeychainQueries.presence(service: service, account: account, format: format)
        let status = runtime.copyMatching(query).status
        return KeychainQueries.itemExists(status: status)
    }

    private func copySecret(_ account: String, format: KeychainItemFormat, allowUI: Bool) -> String? {
        let query = KeychainQueries.read(service: service, account: account, format: format, allowUI: allowUI)
        let result = runtime.copyMatching(query)
        guard result.status == errSecSuccess, let data = result.data,
              let value = String(data: data, encoding: .utf8), !value.isEmpty else { return nil }
        return value
    }

    /// After a successful unlock of a pre-resign item, rewrite so this binary does not prompt again.
    private func migrateStaleAccess(_ account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        if writeTrusted(account, data: data) == errSecSuccess {
            _ = runtime.delete(KeychainQueries.identity(service: service, account: account, format: .fileBased))
        }
    }

    private func writeTrusted(_ account: String, data: Data) -> OSStatus {
        let preferred = KeychainQueries.add(service: service, account: account, data: data,
                                            format: .dataProtection, access: nil)
        let added = addReplacingDuplicate(preferred, format: .dataProtection, account: account)
        if added == errSecSuccess { return added }

        let access = KeychainAccessFactory.currentApplication(name: "Goice API key")
        let fallback = KeychainQueries.add(service: service, account: account, data: data,
                                           format: .fileBased, access: access)
        return addReplacingDuplicate(fallback, format: .fileBased, account: account)
    }

    private func addReplacingDuplicate(_ attributes: [String: Any], format: KeychainItemFormat,
                                       account: String) -> OSStatus {
        var status = runtime.add(attributes)
        if status == errSecDuplicateItem {
            _ = runtime.delete(KeychainQueries.identity(service: service, account: account, format: format))
            status = runtime.add(attributes)
        }
        return status
    }

    private func deleteAllFormats(_ account: String) {
        _ = runtime.delete(KeychainQueries.identity(service: service, account: account, format: .dataProtection))
        _ = runtime.delete(KeychainQueries.identity(service: service, account: account, format: .fileBased))
    }

    private func cachedValue(for account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return cache[account]
    }

    private func storeCache(_ value: String?, for account: String) {
        lock.lock()
        defer { lock.unlock() }
        if let value {
            cache[account] = value
        } else {
            cache.removeValue(forKey: account)
        }
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
