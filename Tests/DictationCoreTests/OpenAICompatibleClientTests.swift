import XCTest
@testable import DictationCore

final class OpenAICompatibleClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func client(status: Int, body: String) -> OpenAICompatibleClient {
        StubURLProtocol.response = (status, Data(body.utf8))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return OpenAICompatibleClient(session: URLSession(configuration: config))
    }

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    func testTranscriptionPostsToOpenAICompatiblePath() async throws {
        let client = client(status: 200, body: #"{"text":"你好世界"}"#)
        let multipart = MultipartAudio(audio: Data([0, 1, 2]), filename: "test.wav", contentType: "audio/wav",
                                       language: "zh", extraFields: ["model": "whisper-1", "prompt": "Voice dictation. Prefer these terms when they fit the speech: Goice."])
        let url = try OpenAICompatibleURL.transcriptions(from: "https://api.openai.com/v1")
        let result = try await client.request(multipart, url: url, apiKey: "test-only-key")
        XCTAssertEqual(result, "你好世界")
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-only-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "GPTVoice")
        let body = String(decoding: multipart.body, as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"model\""))
        XCTAssertTrue(body.contains("whisper-1"))
        XCTAssertTrue(body.contains("name=\"prompt\""))
        XCTAssertTrue(body.contains("Goice"))
        XCTAssertTrue(body.contains("name=\"language\""))
        XCTAssertFalse(body.contains("test-only-key"))
    }

    func testUnauthorizedKeyDoesNotExposeSecret() async {
        let client = client(status: 401, body: #"{"error":{"message":"sk-live-secret"}}"#)
        let multipart = MultipartAudio(audio: Data([1]), filename: "test.wav", contentType: "audio/wav")
        let url = try! OpenAICompatibleURL.transcriptions(from: "http://127.0.0.1:8080")
        do {
            _ = try await client.request(multipart, url: url, apiKey: "sk-live-secret")
            XCTFail("Expected a rejected key")
        } catch {
            XCTAssertEqual(error.localizedDescription, DictationError.apiKeyRejected.localizedDescription)
            XCTAssertFalse(error.localizedDescription.contains("sk-"))
        }
    }

    func testLocalBaseURLOmitsKeyAndStillPosts() async throws {
        let client = client(status: 200, body: #"{"text":"hello"}"#)
        let multipart = MultipartAudio(audio: Data([1]), filename: "test.wav", contentType: "audio/wav",
                                       extraFields: ["model": "whisper-1"])
        let url = try OpenAICompatibleURL.transcriptions(from: "http://127.0.0.1:8080/v1")
        _ = try await client.request(multipart, url: url, apiKey: nil)
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8080/v1/audio/transcriptions")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testConnectionReportsSavedServerWithoutPrintingSecrets() async {
        StubURLProtocol.response = (200, Data(#"{"data":[]}"#.utf8))
        let result = await OpenAICompatibleClient(session: session())
            .testConnection(endpoint: OpenAICompatibleEndpoint(baseURL: "https://api.openai.com/v1", model: "whisper-1"),
                            apiKey: "sk-live-secret")
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.message, "Connected.")
        XCTAssertFalse(result.message.contains("sk-"))
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.absoluteString, "https://api.openai.com/v1/models")
        XCTAssertEqual(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-live-secret")
    }

    func testURLNormalization() throws {
        XCTAssertEqual(try OpenAICompatibleURL.transcriptions(from: "https://api.openai.com").absoluteString,
                       "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(try OpenAICompatibleURL.transcriptions(from: "https://api.openai.com/v1/").absoluteString,
                       "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(try OpenAICompatibleURL.chatCompletions(from: "http://127.0.0.1:8080/v1").absoluteString,
                       "http://127.0.0.1:8080/v1/chat/completions")
        XCTAssertTrue(OpenAICompatibleURL.isLocalHost("http://127.0.0.1:8080/v1"))
        XCTAssertFalse(OpenAICompatibleURL.isLocalHost("https://api.openai.com/v1"))
        XCTAssertThrowsError(try OpenAICompatibleURL.transcriptions(from: "not a url"))
    }
}
