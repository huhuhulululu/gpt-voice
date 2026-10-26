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
        XCTAssertFalse(preferences.chatCleanup)
        XCTAssertEqual(preferences.openAIModel, "whisper-1")
        XCTAssertEqual(AppBrand.displayName, "Goice")
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
}
