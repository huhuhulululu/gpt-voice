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

    func testFreshInstallDefaultsToDeepSeekThroughLarpRouter() {
        let defaults = freshDefaults()
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertTrue(preferences.chatCleanup)
        XCTAssertEqual(preferences.chatCleanupBaseURL, "https://larprouter.com/v1")
        XCTAssertEqual(preferences.chatCleanupModel, "deepseek-v4.1-flash")
        XCTAssertTrue(preferences.chatCleanupIsConfigured)
        preferences.chatCleanupModel = " "
        XCTAssertFalse(preferences.chatCleanupIsConfigured)
        preferences.chatCleanup = false
        XCTAssertFalse(AppPreferences(defaults: defaults).chatCleanup)
    }

    func testGroqKeyIsNeverSentToTheChatServer() async throws {
        let secrets = MemorySecretStore()
        try secrets.setSecret("groq-stt-key", for: KeychainSecretStore.apiKeyAccount)
        ChatRecorder.reset(content: "采菊东篱下，悠然见南山。")
        let model = makeModel(secrets: secrets, transcript: "彩鞠动篱下,悠然见南山。")
        model.transcribeFile(URL(fileURLWithPath: "/no-chat-key.wav"))
        try await waitUntil { if case .finished = model.phase { return true }; return false }
        XCTAssertTrue(ChatRecorder.requests.isEmpty, "Without a chat key, correction is skipped")
        XCTAssertEqual(model.lastTranscript, "彩鞠动篱下,悠然见南山。")

        try secrets.setSecret("chat-server-key", for: KeychainSecretStore.chatAPIKeyAccount)
        model.transcribeFile(URL(fileURLWithPath: "/with-chat-key.wav"))
        try await waitUntil { model.lastTranscript == "采菊东篱下，悠然见南山。" }
        let request = try XCTUnwrap(ChatRecorder.requests.last)
        XCTAssertEqual(request.url?.host, "chat.example.test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer chat-server-key")
        XCTAssertFalse(ChatRecorder.requests.contains {
            $0.value(forHTTPHeaderField: "Authorization")?.contains("groq-stt-key") == true
        })
    }

    func testChatFailureStillDeliversTheLocalText() async throws {
        for status in [401, 503] {
            let secrets = MemorySecretStore()
            try secrets.setSecret("groq-stt-key", for: KeychainSecretStore.apiKeyAccount)
            try secrets.setSecret("chat-server-key", for: KeychainSecretStore.chatAPIKeyAccount)
            ChatRecorder.reset(status: status)
            let model = makeModel(secrets: secrets, transcript: "出禾日当午,观众有老虎。")
            model.lexicon.addReplacement(mishear: "出禾", correct: "锄禾")
            model.transcribeFile(URL(fileURLWithPath: "/chat-\(status).wav"))
            try await waitUntil { model.phase == .finished(.copied(.automaticPasteOff)) }
            XCTAssertEqual(ChatRecorder.requests.count, 1, "HTTP \(status)")
            XCTAssertEqual(model.lastTranscript, "锄禾日当午,观众有老虎。", "HTTP \(status)")
            await model.history.waitForPendingChanges()
            XCTAssertEqual(model.history.entries.first?.text, "锄禾日当午,观众有老虎。")
        }
    }

    func testMissingModelOrURLSkipsChatSilently() async throws {
        let secrets = MemorySecretStore()
        try secrets.setSecret("groq-stt-key", for: KeychainSecretStore.apiKeyAccount)
        try secrets.setSecret("chat-server-key", for: KeychainSecretStore.chatAPIKeyAccount)
        ChatRecorder.reset(content: "should not be used")
        let model = makeModel(secrets: secrets, transcript: "出禾日当午")
        model.lexicon.addReplacement(mishear: "出禾", correct: "锄禾")
        model.preferences.chatCleanupModel = ""
        model.transcribeFile(URL(fileURLWithPath: "/no-model.wav"))
        try await waitUntil { model.phase == .finished(.copied(.automaticPasteOff)) }
        model.preferences.chatCleanupModel = "test-chat-model"
        model.preferences.chatCleanupBaseURL = "  "
        model.transcribeFile(URL(fileURLWithPath: "/no-url.wav"))
        try await waitUntil { model.phase == .finished(.copied(.automaticPasteOff)) }
        XCTAssertTrue(ChatRecorder.requests.isEmpty)
        XCTAssertEqual(model.lastTranscript, "锄禾日当午")
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
        preferences.chatCleanup = true
        preferences.chatCleanupBaseURL = "https://chat.example.test/v1"
        preferences.chatCleanupModel = "test-chat-model"
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
