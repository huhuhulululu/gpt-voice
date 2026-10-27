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
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), HTTPClient.userAgent)
        XCTAssertEqual(HTTPClient.userAgent, "GPTVoice")
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
        XCTAssertEqual(result.message, "Connected. You can dictate now.")
        XCTAssertFalse(result.message.contains("sk-"))
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.absoluteString, "https://api.openai.com/v1/models")
        XCTAssertEqual(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-live-secret")
    }

    func testConnectionForbiddenDoesNotClaimABadKey() async {
        StubURLProtocol.response = (403, Data(#"{"error":{"message":"blocked"}}"#.utf8))
        let result = await OpenAICompatibleClient(session: session())
            .testConnection(endpoint: OpenAICompatibleEndpoint(baseURL: "https://api.groq.com/openai/v1",
                                                               model: "whisper-large-v3"),
                            apiKey: "gsk-test")
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.message.contains("403"))
        XCTAssertFalse(result.message.lowercased().contains("api key"))
        XCTAssertFalse(result.message.contains("gsk-"))
    }

    func testForbiddenResponseDoesNotClaimABadKey() async {
        let client = client(status: 403, body: #"{"error":{"message":"blocked"}}"#)
        let multipart = MultipartAudio(audio: Data([1]), filename: "test.wav", contentType: "audio/wav")
        let url = try! OpenAICompatibleURL.transcriptions(from: "https://api.groq.com/openai/v1")
        do {
            _ = try await client.request(multipart, url: url, apiKey: "gsk-test")
            XCTFail("Expected a denied request")
        } catch {
            XCTAssertEqual(error.localizedDescription, DictationError.service(403).localizedDescription)
            XCTAssertFalse(error.localizedDescription.contains("gsk-"))
        }
    }

    func testURLNormalization() throws {
        XCTAssertEqual(try OpenAICompatibleURL.transcriptions(from: "https://api.openai.com").absoluteString,
                       "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(try OpenAICompatibleURL.transcriptions(from: "https://api.openai.com/v1/").absoluteString,
                       "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(try OpenAICompatibleURL.transcriptions(from: "https://api.groq.com/openai/v1").absoluteString,
                       "https://api.groq.com/openai/v1/audio/transcriptions")
        XCTAssertEqual(try OpenAICompatibleURL.chatCompletions(from: "http://127.0.0.1:8080/v1").absoluteString,
                       "http://127.0.0.1:8080/v1/chat/completions")
        XCTAssertTrue(OpenAICompatibleURL.isLocalHost("http://127.0.0.1:8080/v1"))
        XCTAssertFalse(OpenAICompatibleURL.isLocalHost("https://api.openai.com/v1"))
        XCTAssertThrowsError(try OpenAICompatibleURL.transcriptions(from: "not a url"))
    }

    func testRequestsVerboseJSONExceptForGPT4oModels() {
        let whisper = OpenAICompatibleEndpoint(baseURL: "https://api.groq.com/openai/v1", model: "whisper-large-v3",
                                               language: "zh")
        XCTAssertEqual(OpenAICompatibleClient.transcriptionFields(endpoint: whisper, prompt: "以下是普通话的句子。",
                                                                  verbose: true),
                       ["model": "whisper-large-v3", "prompt": "以下是普通话的句子。",
                        "response_format": "verbose_json"])
        XCTAssertTrue(OpenAICompatibleClient.supportsVerboseJSON(model: "whisper-1"))
        XCTAssertFalse(OpenAICompatibleClient.supportsVerboseJSON(model: "gpt-4o-mini-transcribe"))
    }

    func testVerboseSegmentsDropAHallucinatedOutro() async throws {
        let body = #"{"text":" Ship it. Thank you for watching.","segments":[{"text":" Ship it.","no_speech_prob":0.01,"avg_logprob":-0.2,"compression_ratio":1.1},{"text":" Thank you for watching.","no_speech_prob":0.85,"avg_logprob":-1.4,"compression_ratio":1.0}]}"#
        let client = client(status: 200, body: body)
        let endpoint = OpenAICompatibleEndpoint(baseURL: "https://api.openai.com/v1", model: "whisper-1", language: "")
        let text = try await client.send(audio: Data([1]), filename: "a.wav", contentType: "audio/wav",
                                         endpoint: endpoint, prompt: nil,
                                         url: try OpenAICompatibleURL.transcriptions(from: endpoint.baseURL),
                                         apiKey: nil)
        XCTAssertEqual(text, "Ship it.")
    }

    func testServerWithoutVerboseJSONGetsOnePlainRetry() async throws {
        var calls = 0
        StubURLProtocol.handler = { _ in
            calls += 1
            return calls == 1 ? (400, Data(#"{"error":"response_format"}"#.utf8)) : (200, Data(#"{"text":"hello"}"#.utf8))
        }
        let client = OpenAICompatibleClient(session: session())
        let endpoint = OpenAICompatibleEndpoint(baseURL: "http://127.0.0.1:8080/v1", model: "whisper-1", language: "")
        let url = try OpenAICompatibleURL.transcriptions(from: endpoint.baseURL)
        let text = try await client.send(audio: Data([1]), filename: "a.wav", contentType: "audio/wav",
                                         endpoint: endpoint, prompt: nil, url: url, apiKey: nil)
        XCTAssertEqual(text, "hello")
        XCTAssertEqual(calls, 2)

        calls = 0
        let gpt4o = OpenAICompatibleEndpoint(baseURL: endpoint.baseURL, model: "gpt-4o-transcribe", language: "")
        do {
            _ = try await client.send(audio: Data([1]), filename: "a.wav", contentType: "audio/wav",
                                      endpoint: gpt4o, prompt: nil, url: url, apiKey: nil)
            XCTFail("A plain request has nothing to fall back to")
        } catch {
            XCTAssertEqual(calls, 1)
        }
    }
}
