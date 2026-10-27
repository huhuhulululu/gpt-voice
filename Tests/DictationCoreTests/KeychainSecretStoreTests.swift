import Security
import XCTest
@testable import DictationCore

final class KeychainSecretStoreTests: XCTestCase {
    private let account = KeychainSecretStore.apiKeyAccount
    private let service = "com.vishesh.codex-dictation"

    func testPresenceAndReadQueriesSeparateUIFromUnlock() {
        let presence = KeychainQueries.presence(service: service, account: account, format: .fileBased)
        XCTAssertEqual(presence[kSecUseAuthenticationUI as String] as? String,
                       kSecUseAuthenticationUIFail as String)
        XCTAssertEqual(presence[kSecReturnData as String] as? Bool, false)
        XCTAssertEqual(presence[kSecUseDataProtectionKeychain as String] as? Bool, false)

        let silentRead = KeychainQueries.read(service: service, account: account,
                                              format: .dataProtection, allowUI: false)
        XCTAssertEqual(silentRead[kSecUseAuthenticationUI as String] as? String,
                       kSecUseAuthenticationUIFail as String)
        XCTAssertEqual(silentRead[kSecReturnData as String] as? Bool, true)

        let unlockRead = KeychainQueries.read(service: service, account: account,
                                              format: .fileBased, allowUI: true)
        XCTAssertNil(unlockRead[kSecUseAuthenticationUI as String])
        XCTAssertEqual(unlockRead[kSecReturnData as String] as? Bool, true)
    }

    func testPreferredWriteUsesAfterFirstUnlockDataProtection() {
        let add = KeychainQueries.add(service: service, account: account, data: Data("sk".utf8),
                                      format: .dataProtection, access: nil)
        XCTAssertEqual(add[kSecUseDataProtectionKeychain as String] as? Bool, true)
        XCTAssertEqual(add[kSecAttrAccessible as String] as? String,
                       kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        XCTAssertNil(add[kSecAttrAccess as String])
        XCTAssertFalse(KeychainQueries.itemExists(status: errSecItemNotFound))
    }

    func testContainsSecretNeverRequestsTheSecretBytes() {
        let keychain = FakeKeychain()
        keychain.copyHandler = { query in
            XCTAssertEqual(query[kSecReturnData as String] as? Bool, false)
            XCTAssertEqual(query[kSecUseAuthenticationUI as String] as? String,
                           kSecUseAuthenticationUIFail as String)
            return (errSecInteractionNotAllowed, nil)
        }
        let store = KeychainSecretStore(service: service, runtime: keychain)
        XCTAssertTrue(store.containsSecret(for: account))
        XCTAssertEqual(keychain.copyCount, 1)
        XCTAssertEqual(keychain.addCount, 0)
    }

    func testSecretCachesAfterOneUnlockAndMigratesStaleFileItem() {
        let keychain = FakeKeychain()
        keychain.copyHandler = { query in
            if query[kSecUseDataProtectionKeychain as String] as? Bool == true {
                return (errSecItemNotFound, nil)
            }
            if query[kSecReturnData as String] as? Bool == true {
                return (errSecSuccess, Data("sk-live".utf8))
            }
            return (errSecItemNotFound, nil)
        }
        let store = KeychainSecretStore(service: service, runtime: keychain)
        XCTAssertEqual(store.secret(for: account), "sk-live")
        XCTAssertEqual(store.secret(for: account), "sk-live")
        XCTAssertEqual(store.secret(for: account), "sk-live")
        XCTAssertEqual(keychain.copyCount, 2, "DP miss + file unlock, then cache")
        XCTAssertGreaterThanOrEqual(keychain.addCount, 1)
        XCTAssertEqual(keychain.lastAdd?[kSecUseDataProtectionKeychain as String] as? Bool, true)
        XCTAssertEqual(keychain.lastAdd?[kSecAttrAccessible as String] as? String,
                       kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        XCTAssertTrue(keychain.deletedFileBased)
    }

    func testSetSecretWritesTrustedItemAndServesCacheWithoutCopy() throws {
        let keychain = FakeKeychain()
        let store = KeychainSecretStore(service: service, runtime: keychain)
        try store.setSecret("sk-saved", for: account)
        XCTAssertEqual(store.secret(for: account), "sk-saved")
        XCTAssertEqual(keychain.copyCount, 0)
        XCTAssertEqual(keychain.lastAdd?[kSecUseDataProtectionKeychain as String] as? Bool, true)
        try store.setSecret(nil, for: account)
        XCTAssertNil(store.secret(for: account))
        XCTAssertFalse(store.containsSecret(for: account))
    }

    func testDataProtectionHitDoesNotRewriteOrPromptTwice() {
        let keychain = FakeKeychain()
        keychain.copyHandler = { query in
            if query[kSecUseDataProtectionKeychain as String] as? Bool == true,
               query[kSecReturnData as String] as? Bool == true {
                return (errSecSuccess, Data("sk-dp".utf8))
            }
            return (errSecItemNotFound, nil)
        }
        let store = KeychainSecretStore(service: service, runtime: keychain)
        XCTAssertEqual(store.secret(for: account), "sk-dp")
        XCTAssertEqual(store.secret(for: account), "sk-dp")
        XCTAssertEqual(keychain.copyCount, 1)
        XCTAssertEqual(keychain.addCount, 0)
    }
}

final class FakeKeychain: KeychainRuntime, @unchecked Sendable {
    var copyCount = 0
    var addCount = 0
    var lastAdd: [String: Any]?
    var deletedFileBased = false
    var copyHandler: ([String: Any]) -> (OSStatus, Data?) = { _ in (errSecItemNotFound, nil) }

    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
        copyCount += 1
        return copyHandler(query)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        addCount += 1
        lastAdd = attributes
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        if query[kSecUseDataProtectionKeychain as String] as? Bool == false {
            deletedFileBased = true
        }
        return errSecSuccess
    }
}
