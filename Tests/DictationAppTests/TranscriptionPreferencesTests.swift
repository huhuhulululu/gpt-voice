import Combine
import DictationCore
import XCTest
@testable import GPTVoice

@MainActor
final class TranscriptionPreferencesTests: XCTestCase {
    func testCodexRemainsTheDefaultProvider() {
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: "goice-prefs-\(UUID().uuidString)")!)
        XCTAssertEqual(preferences.transcriptionProvider, .codex)
        XCTAssertTrue(preferences.deterministicCleanup)
        XCTAssertTrue(preferences.chatCleanup)
        XCTAssertEqual(preferences.chatCleanupBaseURL, "https://cpa.aanao.cc/v1")
        XCTAssertEqual(preferences.chatCleanupModel, "gemini-3.5-flash-lite")
        XCTAssertFalse(preferences.soundCues)
        XCTAssertFalse(preferences.hapticCues)
        XCTAssertEqual(preferences.openAIModel, "whisper-1")
        XCTAssertEqual(AppBrand.displayName, "Goice")
    }

    func testGroqPresetFillsCompatibleURLAndModel() {
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: "goice-groq-\(UUID().uuidString)")!)
        let model = AppModel(preferences: preferences,
                             history: TranscriptionHistory(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("gpt-voice-test-\(UUID().uuidString)/history.json")),
                             secrets: MemorySecretStore()) { _ in "ok" }
        defer { model.cleanup() }
        model.applyGroqPreset()
        XCTAssertEqual(preferences.transcriptionProvider, .openAICompatible)
        XCTAssertEqual(preferences.openAIBaseURL, "https://api.groq.com/openai/v1")
        XCTAssertEqual(preferences.openAIModel, "whisper-large-v3")
        XCTAssertEqual(try? OpenAICompatibleURL.transcriptions(from: preferences.openAIBaseURL).absoluteString,
                       "https://api.groq.com/openai/v1/audio/transcriptions")
        XCTAssertEqual(preferences.transcriptionLanguage, "zh")
        XCTAssertEqual(preferences.transcriptionHostTitle, "Groq")
    }

    func testGroqPresetKeepsAnExistingLanguageHint() {
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: "goice-groq-lang-\(UUID().uuidString)")!)
        preferences.transcriptionLanguage = "en"
        let model = AppModel(preferences: preferences,
                             history: TranscriptionHistory(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("gpt-voice-test-\(UUID().uuidString)/history.json")),
                             secrets: MemorySecretStore()) { _ in "ok" }
        defer { model.cleanup() }
        model.applyGroqPreset()
        XCTAssertEqual(preferences.transcriptionLanguage, "en")
        XCTAssertEqual(preferences.openAIModel, "whisper-large-v3")
    }

    func testUnconfiguredOpenAICompatibleOpensTranscriptionSettings() {
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: "goice-recover-\(UUID().uuidString)")!)
        preferences.transcriptionProvider = .openAICompatible
        preferences.openAIBaseURL = "https://api.groq.com/openai/v1"
        let model = AppModel(preferences: preferences,
                             history: TranscriptionHistory(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("gpt-voice-test-\(UUID().uuidString)/history.json")),
                             secrets: MemorySecretStore()) { _ in "ok" }
        defer { model.cleanup() }
        model.refreshStatus()
        model.startDictation()
        guard case .failed(let failure) = model.phase else {
            return XCTFail("Unconfigured Groq should fail before capture")
        }
        XCTAssertEqual(failure.recovery, .transcriptionSettings)
        XCTAssertEqual(failure.overlayActionTitle, "Open Settings")
        model.recoverFromOverlay()
        XCTAssertEqual(model.preferredSettingsPage, .transcription)
    }

    func testOpenAIReadyRequiresKeyUnlessLocal() {
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: "goice-ready-\(UUID().uuidString)")!)
        preferences.transcriptionProvider = .openAICompatible
        preferences.openAIBaseURL = "https://api.openai.com/v1"
        XCTAssertFalse(preferences.openAICompatibleIsReady(hasAPIKey: false))
        XCTAssertTrue(preferences.openAICompatibleIsReady(hasAPIKey: true))
        preferences.openAIBaseURL = "http://127.0.0.1:8080/v1"
        XCTAssertTrue(preferences.openAICompatibleIsReady(hasAPIKey: false))
    }

    func testMissingRequirementSwitchesWithProvider() {
        let defaults = UserDefaults(suiteName: "goice-model-\(UUID().uuidString)")!
        let preferences = AppPreferences(defaults: defaults)
        let secrets = MemorySecretStore()
        let model = AppModel(preferences: preferences, history: TranscriptionHistory(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("gpt-voice-test-\(UUID().uuidString)/history.json")), secrets: secrets) { _ in "ok" }
        defer { model.cleanup() }
        preferences.transcriptionProvider = .openAICompatible
        preferences.openAIBaseURL = "https://api.openai.com/v1"
        model.refreshStatus()
        XCTAssertTrue(model.missingRequirements.contains("Configure transcription"))
        XCTAssertFalse(model.transcriptionIsReady)
        try? secrets.setSecret("sk-test", for: KeychainSecretStore.apiKeyAccount)
        model.refreshStatus()
        XCTAssertTrue(model.transcriptionIsReady)
        XCTAssertFalse(model.missingRequirements.contains("Configure transcription"))
    }

    func testInjectedTranscriptStillGetsLocalCleanup() async {
        let defaults = UserDefaults(suiteName: "goice-clean-\(UUID().uuidString)")!
        let preferences = AppPreferences(defaults: defaults)
        preferences.deterministicCleanup = true
        preferences.chatCleanup = false
        let model = AppModel(preferences: preferences, pasteboard: NSPasteboard.withUniqueName(),
                             history: TranscriptionHistory(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("gpt-voice-test-\(UUID().uuidString)/history.json")),
                             secrets: MemorySecretStore()) { _ in "Um, a clear thought. Thank you." }
        defer { model.cleanup() }
        let finished = expectation(description: "cleanup finished")
        let observer = model.$phase.sink { phase in
            if phase == .finished(.previewed) { finished.fulfill() }
        }
        defer { observer.cancel() }
        model.transcribeFile(URL(fileURLWithPath: "/tmp/goice-cleanup.wav"), forPractice: true)
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(model.practiceTranscript, "a clear thought.")
        XCTAssertEqual(model.lastTranscript, "a clear thought.")
    }

    func testCodexTranscriptionNeverReadsTheKeychain() async throws {
        let secrets = CountingSecretStore([KeychainSecretStore.apiKeyAccount: "sk-stale"])
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: "goice-codex-key-\(UUID().uuidString)")!)
        preferences.transcriptionProvider = .codex
        let model = AppModel(preferences: preferences,
                             history: TranscriptionHistory(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("gpt-voice-test-\(UUID().uuidString)/history.json")),
                             secrets: secrets) { _ in "测试测试测试" }
        defer { model.cleanup() }
        model.transcribeFile(URL(fileURLWithPath: "/tmp/goice-codex.wav"), forPractice: true)
        try await waitUntil { model.phase == .finished(.previewed) }
        XCTAssertEqual(model.practiceTranscript, "测试测试测试")
        XCTAssertEqual(secrets.secretCalls, 0)
    }

    func testDeniedKeychainUnlockOffersRetryInsteadOfAKeylessRequest() async throws {
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: "goice-denied-\(UUID().uuidString)")!)
        preferences.transcriptionProvider = .openAICompatible
        preferences.openAIBaseURL = "https://api.groq.com/openai/v1"
        let model = AppModel(preferences: preferences,
                             history: TranscriptionHistory(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("gpt-voice-test-\(UUID().uuidString)/history.json")),
                             secrets: DenyingSecretStore()) { _ in
            XCTFail("No request may be sent without the key")
            return "never"
        }
        defer { model.cleanup() }
        model.refreshStatus()
        XCTAssertTrue(model.transcriptionIsReady)
        model.transcribeFile(URL(fileURLWithPath: "/tmp/goice-denied.wav"), forPractice: true)
        try await waitUntil { if case .failed = model.phase { return true }; return false }
        guard case .failed(let failure) = model.phase else { return XCTFail("Expected a failure") }
        XCTAssertEqual(failure.recovery, .retry)
        XCTAssertEqual(failure.overlayMessage, "Allow Keychain access")
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let limit = Date().addingTimeInterval(3)
        while !condition(), Date() < limit { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(condition())
    }

    func testRefreshStatusDoesNotUnlockTheAPIKey() {
        let secrets = CountingSecretStore([KeychainSecretStore.apiKeyAccount: "sk-test"])
        let model = AppModel(preferences: AppPreferences(defaults: UserDefaults(suiteName: "goice-key-\(UUID().uuidString)")!),
                             history: TranscriptionHistory(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("gpt-voice-test-\(UUID().uuidString)/history.json")),
                             secrets: secrets) { _ in "ok" }
        defer { model.cleanup() }
        model.refreshStatus()
        XCTAssertEqual(secrets.secretCalls, 0)
        XCTAssertGreaterThan(secrets.containsCalls, 0)
        XCTAssertTrue(model.openAIKeyPresent)
    }
}

/// The key exists, but the user chose Deny in SecurityAgent.
private final class DenyingSecretStore: SecretStore, @unchecked Sendable {
    func secret(for account: String) -> String? { nil }
    func readSecret(for account: String) -> SecretRead {
        account == KeychainSecretStore.apiKeyAccount ? .unavailable : .missing
    }
    func containsSecret(for account: String) -> Bool { account == KeychainSecretStore.apiKeyAccount }
    func setSecret(_ value: String?, for account: String) throws {}
}

/// Counts Keychain reads. Menu/status must use containsSecret, never secret().
private final class CountingSecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]
    private(set) var secretCalls = 0
    private(set) var containsCalls = 0

    init(_ initial: [String: String] = [:]) {
        values = initial
    }

    func secret(for account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        secretCalls += 1
        return values[account]
    }

    func containsSecret(for account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        containsCalls += 1
        return values[account] != nil
    }

    func setSecret(_ value: String?, for account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if let value, !value.isEmpty {
            values[account] = value
        } else {
            values.removeValue(forKey: account)
        }
    }
}
