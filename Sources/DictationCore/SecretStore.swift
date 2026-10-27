import Foundation
import Security

/// Result of reading a secret. `unavailable` means the item exists but macOS did not release it
/// (Deny, Cancel, or a locked keychain), so callers must not treat it as "no key".
public enum SecretRead: Equatable, Sendable {
    case value(String)
    case missing
    case unavailable

    public var value: String? {
        if case .value(let value) = self { return value }
        return nil
    }
}

/// Stores API keys. Never logs values. UserDefaults is not used for secrets.
public protocol SecretStore: Sendable {
    func secret(for account: String) -> String?
    func readSecret(for account: String) -> SecretRead
    /// Presence only. Must not decrypt the item or show Keychain / SecurityAgent UI.
    func containsSecret(for account: String) -> Bool
    func setSecret(_ value: String?, for account: String) throws
}

public extension SecretStore {
    func readSecret(for account: String) -> SecretRead {
        secret(for: account).map(SecretRead.value) ?? .missing
    }
}

/// Keychain dictionaries. Login (file-based) keychain only: the Data Protection keychain needs a
/// keychain-access-groups entitlement and provisioning profile that this Developer ID app does not have.
public enum KeychainQueries {
    public static func identity(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// Existence only. No secret bytes, so no decrypt and no unlock sheet.
    public static func presence(service: String, account: String) -> [String: Any] {
        var query = identity(service: service, account: account)
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        return query
    }

    /// Attributes are not encrypted, so this never prompts. Carries the owner marker.
    public static func attributes(service: String, account: String) -> [String: Any] {
        var query = identity(service: service, account: account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        return query
    }

    /// The one read that may show SecurityAgent, when the item's ACL predates this signature.
    public static func data(service: String, account: String) -> [String: Any] {
        var query = identity(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    public static func delete(service: String, account: String) -> [String: Any] {
        identity(service: service, account: account)
    }

    /// No explicit access object: the default ACL and partition trust the signature that adds the item.
    public static func add(service: String, account: String, data: Data, owner: String) -> [String: Any] {
        var attributes = identity(service: service, account: account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrGeneric as String] = Data(owner.utf8)
        attributes[kSecAttrLabel as String] = "Goice API key"
        return attributes
    }

    public static func owner(in attributes: [String: Any]?) -> String? {
        guard let data = attributes?[kSecAttrGeneric as String] as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Locked or ACL-protected items still count as present so status checks never prompt.
    public static func itemExists(status: OSStatus) -> Bool {
        switch status {
        case errSecSuccess, errSecInteractionNotAllowed, errSecAuthFailed:
            return true
        default:
            return false
        }
    }
}

public struct KeychainReadResult {
    public var status: OSStatus
    public var data: Data?
    public var attributes: [String: Any]?

    public init(status: OSStatus, data: Data? = nil, attributes: [String: Any]? = nil) {
        self.status = status
        self.data = data
        self.attributes = attributes
    }
}

public protocol KeychainRuntime: Sendable {
    func copyMatching(_ query: [String: Any]) -> KeychainReadResult
    func add(_ attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

public struct SecurityKeychainRuntime: KeychainRuntime {
    public init() {}

    public func copyMatching(_ query: [String: Any]) -> KeychainReadResult {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return KeychainReadResult(status: status, data: item as? Data, attributes: item as? [String: Any])
    }

    public func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    public func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

/// The signature the login keychain trusts: the team for Developer ID, the CDHash for ad-hoc builds.
public enum CodeSigningIdentity {
    public static let current: String = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return "unsigned" }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return "unsigned" }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: UInt32(kSecCSSigningInformation)),
                                            &information) == errSecSuccess,
              let info = information as? [String: Any] else { return "unsigned" }
        if let team = info[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty {
            return "team:" + team
        }
        if let unique = info[kSecCodeInfoUnique as String] as? Data {
            return "cdhash:" + unique.map { String(format: "%02x", $0) }.joined()
        }
        return "unsigned"
    }()
}

/// API keys in the login keychain.
///
/// Each item records the signature that wrote it. A re-signed build (new CDHash or team) reads the old
/// item once — the only time SecurityAgent can appear — then re-adds it under its own signature, so later
/// reads and relaunches of the same signature are silent. The value is cached for the process lifetime,
/// so recordings never touch the keychain after the first read.
public final class KeychainSecretStore: SecretStore, @unchecked Sendable {
    public static let apiKeyAccount = "openai-compatible-api-key"
    public static let chatAPIKeyAccount = "openai-compatible-chat-api-key"
    /// Holds a copy while an item is replaced, so a failed replace never loses the key.
    static let stagingSuffix = ".staging"

    private let service: String
    private let runtime: KeychainRuntime
    private let owner: String
    private let cacheLock = NSLock()
    /// One keychain operation at a time, so concurrent callers share a single prompt.
    private let operationLock = NSLock()
    private var cache: [String: String] = [:]

    public init(service: String = "com.vishesh.codex-dictation",
                runtime: KeychainRuntime = SecurityKeychainRuntime(),
                owner: String = CodeSigningIdentity.current) {
        self.service = service
        self.runtime = runtime
        self.owner = owner
    }

    public func containsSecret(for account: String) -> Bool {
        if cached(account) != nil { return true }
        return [account, staging(account)].contains { slot in
            KeychainQueries.itemExists(status: runtime.copyMatching(
                KeychainQueries.presence(service: service, account: slot)).status)
        }
    }

    public func secret(for account: String) -> String? {
        readSecret(for: account).value
    }

    public func readSecret(for account: String) -> SecretRead {
        if let value = cached(account) { return .value(value) }
        operationLock.lock()
        defer { operationLock.unlock() }
        if let value = cached(account) { return .value(value) }

        let primary = slot(account)
        let backup = slot(staging(account))
        let source: String
        let ownedByThisSignature: Bool
        if primary.exists, primary.owner == owner {
            (source, ownedByThisSignature) = (account, true)
        } else if backup.exists, backup.owner == owner {
            (source, ownedByThisSignature) = (staging(account), true)
        } else if primary.exists {
            (source, ownedByThisSignature) = (account, false)
        } else if backup.exists {
            (source, ownedByThisSignature) = (staging(account), false)
        } else {
            return .missing
        }

        let read = runtime.copyMatching(KeychainQueries.data(service: service, account: source))
        guard read.status == errSecSuccess, let data = read.data,
              let value = String(data: data, encoding: .utf8), !value.isEmpty else {
            return read.status == errSecItemNotFound ? .missing : .unavailable
        }
        store(value, for: account)
        if !ownedByThisSignature || source != account {
            reown(account, data: data)
        }
        return .value(value)
    }

    public func setSecret(_ value: String?, for account: String) throws {
        operationLock.lock()
        defer { operationLock.unlock() }
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else {
            _ = runtime.delete(KeychainQueries.delete(service: service, account: account))
            _ = runtime.delete(KeychainQueries.delete(service: service, account: staging(account)))
            store(nil, for: account)
            return
        }
        guard write(account, data: data) else { throw DictationError.invalidCredentials }
        store(value, for: account)
    }

    // MARK: Private

    private func staging(_ account: String) -> String { account + Self.stagingSuffix }

    private func slot(_ account: String) -> (exists: Bool, owner: String?) {
        let result = runtime.copyMatching(KeychainQueries.attributes(service: service, account: account))
        return (KeychainQueries.itemExists(status: result.status), KeychainQueries.owner(in: result.attributes))
    }

    /// Re-adds the key under this signature. Failures keep whatever copy already works.
    private func reown(_ account: String, data: Data) {
        _ = write(account, data: data)
    }

    /// Writes a staging copy first, and removes the primary item only once that copy exists, so no
    /// failure can lose the key. Returns true when a copy this signature owns holds `data`: the primary
    /// slot, or staging if the old primary item cannot be removed.
    private func write(_ account: String, data: Data) -> Bool {
        let staging = staging(account)
        _ = runtime.delete(KeychainQueries.delete(service: service, account: staging))
        guard runtime.add(KeychainQueries.add(service: service, account: staging, data: data,
                                              owner: owner)) == errSecSuccess else { return false }
        _ = runtime.delete(KeychainQueries.delete(service: service, account: account))
        if runtime.add(KeychainQueries.add(service: service, account: account, data: data,
                                           owner: owner)) == errSecSuccess {
            _ = runtime.delete(KeychainQueries.delete(service: service, account: staging))
        }
        return true
    }

    private func cached(_ account: String) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache[account]
    }

    private func store(_ value: String?, for account: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
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
