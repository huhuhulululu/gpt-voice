import AppKit
import DictationCore
import XCTest
@testable import GPTVoice

/// Records chat requests so tests can see which key went to which host.
private final class ChatRecorder: URLProtocol {
    static var status = 200
    static var content = ""
    static var requests: [URLRequest] = []

    static func reset(status: Int = 200, content: String = "") {
        self.status = status
        self.content = content
        requests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let object: [String: Any] = ["choices": [["message": ["content": Self.content]]]]
        let body = Self.status == 200 ? (try? JSONSerialization.data(withJSONObject: object)) ?? Data() : Data()
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class ChatCleanupAppTests: XCTestCase {
    private var cleanups: [() -> Void] = []

    override func tearDown() {
        cleanups.forEach { $0() }
        cleanups = []
        super.tearDown()
    }

    func testFreshInstallUsesCPAWithChatCleanupOn() {
        let preferences = AppPreferences(defaults: freshDefaults())
        XCTAssertTrue(preferences.chatCleanup)
        XCTAssertEqual(preferences.chatCleanupBaseURL, "https://cpa.aanao.cc/v1")
        XCTAssertEqual(preferences.chatCleanupModel, "gemini-3.5-flash-lite")
        XCTAssertEqual(preferences.chatCleanupEndpoint, "https://cpa.aanao.cc/v1")
    }

    func testOldDefaultsMoveToCPAOnceAndALaterChoiceSticks() {
        let defaults = freshDefaults()
        defaults.set(false, forKey: "chatCleanup")
        defaults.set("", forKey: "chatCleanupBaseURL")
        defaults.set("gpt-4o-mini", forKey: "chatCleanupModel")
        let migrated = AppPreferences(defaults: defaults)
        XCTAssertTrue(migrated.chatCleanup)
        XCTAssertEqual(migrated.chatCleanupBaseURL, "https://cpa.aanao.cc/v1")
        XCTAssertEqual(migrated.chatCleanupModel, "gemini-3.5-flash-lite")
        migrated.chatCleanup = false
        migrated.chatCleanupModel = "my-model"
        let reopened = AppPreferences(defaults: defaults)
        XCTAssertFalse(reopened.chatCleanup)
        XCTAssertEqual(reopened.chatCleanupModel, "my-model")

        let custom = freshDefaults()
        custom.set("http://127.0.0.1:8080/v1", forKey: "chatCleanupBaseURL")
        XCTAssertEqual(AppPreferences(defaults: custom).chatCleanupBaseURL, "http://127.0.0.1:8080/v1")
    }

    func testGroqKeyIsNeverSentToCPA() async throws {
        let secrets = MemorySecretStore()
        try secrets.setSecret("groq-stt-key", for: KeychainSecretStore.apiKeyAccount)
        ChatRecorder.reset(content: "采菊东篱下，悠然见南山。")
        let model = makeModel(secrets: secrets, transcript: "彩鞠动篱下,悠然见南山。")
        model.transcribeFile(URL(fileURLWithPath: "/no-chat-key.wav"))
        try await waitUntil { if case .finished = model.phase { return true }; return false }
        XCTAssertTrue(ChatRecorder.requests.isEmpty, "Without a CPA key, correction is skipped")
        XCTAssertEqual(model.lastTranscript, "彩鞠动篱下,悠然见南山。")

        try secrets.setSecret("cpa-chat-key", for: KeychainSecretStore.chatAPIKeyAccount)
        model.transcribeFile(URL(fileURLWithPath: "/with-chat-key.wav"))
        try await waitUntil { model.lastTranscript == "采菊东篱下，悠然见南山。" }
        let request = try XCTUnwrap(ChatRecorder.requests.last)
        XCTAssertEqual(request.url?.host, "cpa.aanao.cc")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer cpa-chat-key")
        XCTAssertFalse(ChatRecorder.requests.contains {
            $0.value(forHTTPHeaderField: "Authorization")?.contains("groq-stt-key") == true
        })
    }

    func testCPAFailureStillDeliversTheLocalText() async throws {
        for status in [401, 503] {
            let secrets = MemorySecretStore()
            try secrets.setSecret("groq-stt-key", for: KeychainSecretStore.apiKeyAccount)
            try secrets.setSecret("cpa-chat-key", for: KeychainSecretStore.chatAPIKeyAccount)
            ChatRecorder.reset(status: status)
            let model = makeModel(secrets: secrets, transcript: "出禾日当午,观众有老虎。")
            model.lexicon.addReplacement(mishear: "出禾", correct: "锄禾")
            model.transcribeFile(URL(fileURLWithPath: "/cpa-\(status).wav"))
            try await waitUntil { model.phase == .finished(.copied(.automaticPasteOff)) }
            XCTAssertEqual(ChatRecorder.requests.count, 1, "HTTP \(status)")
            XCTAssertEqual(model.lastTranscript, "锄禾日当午,观众有老虎。", "HTTP \(status)")
            await model.history.waitForPendingChanges()
            XCTAssertEqual(model.history.entries.first?.text, "锄禾日当午,观众有老虎。")
        }
    }

    // MARK: Helpers

    private func freshDefaults() -> UserDefaults {
        let suite = "goice-chat-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        cleanups.append { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func makeModel(secrets: SecretStore, transcript: String) -> AppModel {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("goice-chat-\(UUID().uuidString)")
        let preferences = AppPreferences(defaults: freshDefaults())
        preferences.transcriptionProvider = .openAICompatible
        preferences.openAIBaseURL = "https://api.groq.com/openai/v1"
        preferences.openAIModel = "whisper-large-v3"
        preferences.transcriptionLanguage = "zh"
        preferences.automaticPaste = false
        let clipboard = NSPasteboard.withUniqueName()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ChatRecorder.self]
        let model = AppModel(preferences: preferences, pasteboard: clipboard,
                             history: TranscriptionHistory(fileURL: directory.appendingPathComponent("history.json")),
                             secrets: secrets, chatSession: URLSession(configuration: config)) { _ in transcript }
        model.refreshStatus()
        cleanups.append {
            model.cleanup()
            clipboard.releaseGlobally()
            try? FileManager.default.removeItem(at: directory)
        }
        return model
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let limit = Date().addingTimeInterval(3)
        while !condition(), Date() < limit { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(condition())
    }
}
