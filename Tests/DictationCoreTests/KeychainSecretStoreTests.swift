import Foundation
import Security
import XCTest
@testable import DictationCore

final class KeychainSecretStoreTests: XCTestCase {
    private let account = KeychainSecretStore.apiKeyAccount
    private let service = "com.vishesh.codex-dictation"
    private var staging: String { account + KeychainSecretStore.stagingSuffix }

    func testQueriesSeparatePresenceFromTheOneReadThatMayPrompt() {
        let presence = KeychainQueries.presence(service: service, account: account)
        XCTAssertEqual(presence[kSecReturnData as String] as? Bool, false)
        XCTAssertEqual(presence[kSecUseAuthenticationUI as String] as? String, kSecUseAuthenticationUIFail as String)

        let attributes = KeychainQueries.attributes(service: service, account: account)
        XCTAssertEqual(attributes[kSecReturnAttributes as String] as? Bool, true)
        XCTAssertNil(attributes[kSecReturnData as String])
        XCTAssertEqual(attributes[kSecUseAuthenticationUI as String] as? String,
                       kSecUseAuthenticationUIFail as String)

        let data = KeychainQueries.data(service: service, account: account)
        XCTAssertEqual(data[kSecReturnData as String] as? Bool, true)

        let add = KeychainQueries.add(service: service, account: account, data: Data("sk".utf8), owner: "team:T")
        XCTAssertEqual(add[kSecAttrGeneric as String] as? Data, Data("team:T".utf8))
        XCTAssertNil(add[kSecAttrAccess as String], "Default ACL trusts the signature that adds the item")
        for query in [presence, attributes, data, add] {
            XCTAssertNil(query[kSecUseDataProtectionKeychain as String], "No entitlement for the Data Protection keychain")
        }
        XCTAssertTrue(KeychainQueries.itemExists(status: errSecInteractionNotAllowed))
        XCTAssertFalse(KeychainQueries.itemExists(status: errSecItemNotFound))
    }

    func testMenuPresenceNeverDecryptsOrPrompts() {
        let keychain = FakeKeychain(reader: "team:NEW")
        keychain.seed(account, value: "sk-old", trustedBy: "cdhash:old", owner: nil)
        let store = KeychainSecretStore(service: service, runtime: keychain, owner: "team:NEW")
        XCTAssertTrue(store.containsSecret(for: account))
        XCTAssertEqual(keychain.dataReads, 0)
        XCTAssertEqual(keychain.prompts, 0)
    }

    func testResignedBuildPromptsOnceThenStaysSilentAcrossRecordingsAndRelaunch() {
        let keychain = FakeKeychain(reader: "team:NEW")
        keychain.seed(account, value: "sk-live", trustedBy: "cdhash:adhoc", owner: nil)

        let first = KeychainSecretStore(service: service, runtime: keychain, owner: "team:NEW")
        for _ in 0..<5 { XCTAssertEqual(first.readSecret(for: account), .value("sk-live")) }
        XCTAssertEqual(keychain.prompts, 1, "One unlock for the whole process")
        XCTAssertEqual(keychain.dataReads, 1, "Recordings after the first use the cache")
        XCTAssertEqual(keychain.items[account]?.trustedBy, "team:NEW")
        XCTAssertEqual(keychain.items[account]?.owner, "team:NEW")
        XCTAssertNil(keychain.items[staging])

        let relaunched = KeychainSecretStore(service: service, runtime: keychain, owner: "team:NEW")
        XCTAssertEqual(relaunched.readSecret(for: account), .value("sk-live"))
        XCTAssertEqual(keychain.prompts, 1, "Same signature after relaunch reads silently")
    }

    func testMigrationNeverLosesTheKeyWhenTheOldItemCannotBeRemoved() {
        let keychain = FakeKeychain(reader: "team:NEW")
        keychain.deleteBlockedForUntrusted = true
        keychain.seed(account, value: "sk-live", trustedBy: "cdhash:adhoc", owner: nil)

        let first = KeychainSecretStore(service: service, runtime: keychain, owner: "team:NEW")
        XCTAssertEqual(first.readSecret(for: account), .value("sk-live"))
        XCTAssertEqual(keychain.items[account]?.value, "sk-live")
        XCTAssertEqual(keychain.items[staging]?.trustedBy, "team:NEW")

        let relaunched = KeychainSecretStore(service: service, runtime: keychain, owner: "team:NEW")
        XCTAssertEqual(relaunched.readSecret(for: account), .value("sk-live"))
        XCTAssertTrue(relaunched.containsSecret(for: account))
        XCTAssertEqual(keychain.prompts, 1, "The owned staging copy is read without a sheet")
    }

    func testFailedStagingWriteKeepsTheOriginalItem() {
        let keychain = FakeKeychain(reader: "team:NEW")
        keychain.addFailures = [staging]
        keychain.seed(account, value: "sk-live", trustedBy: "cdhash:adhoc", owner: nil)
        let store = KeychainSecretStore(service: service, runtime: keychain, owner: "team:NEW")
        XCTAssertEqual(store.readSecret(for: account), .value("sk-live"))
        XCTAssertEqual(keychain.items[account]?.value, "sk-live", "Primary stays when no safe copy exists")
    }

    func testDeniedUnlockIsUnavailableAndNotCached() {
        let keychain = FakeKeychain(reader: "team:NEW")
        keychain.promptAnswer = errSecAuthFailed
        keychain.seed(account, value: "sk-live", trustedBy: "cdhash:adhoc", owner: nil)
        let store = KeychainSecretStore(service: service, runtime: keychain, owner: "team:NEW")
        XCTAssertEqual(store.readSecret(for: account), .unavailable)
        XCTAssertNil(store.secret(for: account))
        XCTAssertEqual(keychain.items[account]?.value, "sk-live")

        keychain.promptAnswer = errSecSuccess
        XCTAssertEqual(store.readSecret(for: account), .value("sk-live"), "Retry can still unlock")
    }

    func testMissingKeyIsMissingWithoutAPrompt() {
        let keychain = FakeKeychain(reader: "team:NEW")
        let store = KeychainSecretStore(service: service, runtime: keychain, owner: "team:NEW")
        XCTAssertEqual(store.readSecret(for: KeychainSecretStore.chatAPIKeyAccount), .missing)
        XCTAssertEqual(keychain.prompts, 0)
        XCTAssertEqual(keychain.dataReads, 0)
    }

    func testSaveWritesAnOwnedItemAndRelaunchReadsSilently() throws {
        let keychain = FakeKeychain(reader: "team:NEW")
        keychain.seed(account, value: "sk-old", trustedBy: "cdhash:adhoc", owner: nil)
        let store = KeychainSecretStore(service: service, runtime: keychain, owner: "team:NEW")
        try store.setSecret("sk-new", for: account)
        XCTAssertEqual(store.readSecret(for: account), .value("sk-new"))
        XCTAssertEqual(keychain.dataReads, 0, "Save fills the cache")

        let relaunched = KeychainSecretStore(service: service, runtime: keychain, owner: "team:NEW")
        XCTAssertEqual(relaunched.readSecret(for: account), .value("sk-new"))
        XCTAssertEqual(keychain.prompts, 0)
        XCTAssertNil(keychain.items[staging])
    }

    func testClearRemovesEveryCopy() throws {
        let keychain = FakeKeychain(reader: "team:NEW")
        let store = KeychainSecretStore(service: service, runtime: keychain, owner: "team:NEW")
        try store.setSecret("sk-new", for: account)
        try store.setSecret(nil, for: account)
        XCTAssertNil(store.secret(for: account))
        XCTAssertFalse(store.containsSecret(for: account))
        XCTAssertTrue(keychain.items.isEmpty)
    }

    func testConcurrentReadsShareOneUnlock() {
        let keychain = FakeKeychain(reader: "team:NEW")
        keychain.seed(account, value: "sk-live", trustedBy: "cdhash:adhoc", owner: nil)
        let store = KeychainSecretStore(service: service, runtime: keychain, owner: "team:NEW")
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            XCTAssertEqual(store.readSecret(for: account), .value("sk-live"))
        }
        XCTAssertEqual(keychain.prompts, 1)
    }
}

/// Login keychain model: an item decrypts silently only for the signature that added it.
/// Other signatures get a SecurityAgent sheet, answered with `promptAnswer`.
final class FakeKeychain: KeychainRuntime, @unchecked Sendable {
    struct Item {
        var value: String
        var trustedBy: String
        var owner: String?
    }

    let reader: String
    private let lock = NSLock()
    var items: [String: Item] = [:]
    var prompts = 0
    var dataReads = 0
    var promptAnswer: OSStatus = errSecSuccess
    var deleteBlockedForUntrusted = false
    var addFailures: Set<String> = []

    init(reader: String) {
        self.reader = reader
    }

    func seed(_ account: String, value: String, trustedBy: String, owner: String?) {
        items[account] = Item(value: value, trustedBy: trustedBy, owner: owner)
    }

    func copyMatching(_ query: [String: Any]) -> KeychainReadResult {
        lock.lock()
        defer { lock.unlock() }
        guard let account = query[kSecAttrAccount as String] as? String, let item = items[account] else {
            return KeychainReadResult(status: errSecItemNotFound)
        }
        if query[kSecReturnData as String] as? Bool == true {
            dataReads += 1
            if item.trustedBy != reader {
                if query[kSecUseAuthenticationUI as String] != nil {
                    return KeychainReadResult(status: errSecInteractionNotAllowed)
                }
                prompts += 1
                guard promptAnswer == errSecSuccess else { return KeychainReadResult(status: promptAnswer) }
            }
            return KeychainReadResult(status: errSecSuccess, data: Data(item.value.utf8))
        }
        if query[kSecReturnAttributes as String] as? Bool == true {
            var attributes: [String: Any] = [:]
            if let owner = item.owner { attributes[kSecAttrGeneric as String] = Data(owner.utf8) }
            return KeychainReadResult(status: errSecSuccess, attributes: attributes)
        }
        return KeychainReadResult(status: errSecSuccess)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        guard let account = attributes[kSecAttrAccount as String] as? String,
              let data = attributes[kSecValueData as String] as? Data else { return errSecParam }
        if addFailures.contains(account) { return errSecParam }
        guard items[account] == nil else { return errSecDuplicateItem }
        let owner = (attributes[kSecAttrGeneric as String] as? Data).flatMap { String(data: $0, encoding: .utf8) }
        items[account] = Item(value: String(decoding: data, as: UTF8.self), trustedBy: reader, owner: owner)
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        guard let account = query[kSecAttrAccount as String] as? String, let item = items[account] else {
            return errSecItemNotFound
        }
        if deleteBlockedForUntrusted, item.trustedBy != reader { return errSecInteractionNotAllowed }
        items[account] = nil
        return errSecSuccess
    }
}
