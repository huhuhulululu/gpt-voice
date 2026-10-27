import XCTest
@testable import DictationCore

final class ChatCleanupTests: XCTestCase {
    private let chatURL = "https://chat.example.test/v1"
    private let poemContext = ChatCleanupContext(
        terms: ["锄禾日当午", "采菊东篱下", "悠然见南山"],
        corrections: [VocabularyReplacement(mishear: "彩鞠动篱下", correct: "采菊东篱下"),
                      VocabularyReplacement(mishear: "出禾", correct: "锄禾")])

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func reply(_ content: String) -> Data {
        let object: [String: Any] = ["choices": [["message": ["role": "assistant", "content": content]]]]
        return try! JSONSerialization.data(withJSONObject: object)
    }

    func testSystemPromptCarriesTermsAndCorrectionsWithoutDuplicates() {
        let prompt = ChatCleanupClient.systemPrompt(context: poemContext)
        XCTAssertTrue(prompt.contains("常用词): 锄禾日当午、采菊东篱下、悠然见南山、锄禾"))
        XCTAssertTrue(prompt.contains("彩鞠动篱下 → 采菊东篱下; 出禾 → 锄禾"))
        XCTAssertTrue(prompt.contains("Never translate"))
        XCTAssertTrue(prompt.contains("Do not replace an ordinary word"))
        XCTAssertTrue(prompt.contains("不确定时原样返回"))
        XCTAssertFalse(ChatCleanupClient.systemPrompt().contains("常用词"))
        let many = ChatCleanupContext(terms: (0..<100).map { "t\($0)" })
        XCTAssertFalse(ChatCleanupClient.systemPrompt(context: many).contains("t40"))
    }

    func testTranscriptionKeyIsSharedOnlyWithTheSameHost() {
        XCTAssertFalse(ChatCleanupClient.canShareTranscriptionKey(chatBaseURL: chatURL,
                                                                  transcriptionBaseURL: "https://api.groq.com/openai/v1"))
        XCTAssertTrue(ChatCleanupClient.canShareTranscriptionKey(chatBaseURL: "https://API.groq.com/openai/v1",
                                                                 transcriptionBaseURL: "https://api.groq.com/openai/v1"))
        XCTAssertFalse(ChatCleanupClient.canShareTranscriptionKey(chatBaseURL: "", transcriptionBaseURL: chatURL))
    }

    func testRequestSendsLexiconAwarePromptAndReturnsTheFix() async throws {
        StubURLProtocol.response = (200, reply("锄禾日当午，汗滴禾下土。"))
        let text = try await ChatCleanupClient.clean("锄禾日当午，棺中有老虎。", model: "test-chat-model",
                                                     baseURL: chatURL, apiKey: "chatURL-test", context: poemContext,
                                                     session: session())
        XCTAssertEqual(text, "锄禾日当午，汗滴禾下土。")
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://chat.example.test/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer chatURL-test")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(StubURLProtocol.lastBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "test-chat-model")
        XCTAssertEqual(body["temperature"] as? Int, 0)
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages.first?["role"], "system")
        XCTAssertTrue(messages.first?["content"]?.contains("采菊东篱下") == true)
        XCTAssertEqual(messages.last, ["role": "user", "content": "锄禾日当午，棺中有老虎。"])
    }

    func testPipelineAppliesLexiconThenChat() async {
        StubURLProtocol.response = (200, reply("采菊东篱下，悠然见南山。"))
        let result = await TranscriptPostProcessor.applyReporting(
            "彩鞠动篱下,悠然见南山。", deterministicCleanup: true, extraFilterWords: [],
            replacements: poemContext.corrections, chineseScript: .simplified,
            chat: ("test-chat-model", chatURL, "chatURL-test"), chatContext: poemContext, session: session())
        XCTAssertEqual(result.text, "采菊东篱下，悠然见南山。")
        XCTAssertEqual(result.beforeReplacements, "彩鞠动篱下,悠然见南山。")
        let body = String(decoding: StubURLProtocol.lastBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("采菊东篱下,悠然见南山。"), "Chat sees the text after exact corrections")
    }

    func testOrdinaryLineComesBackUnchanged() async {
        StubURLProtocol.response = (200, reply("老板,帮我把鸟花拿过来。"))
        let text = await TranscriptPostProcessor.apply(
            "老板,帮我把鸟花拿过来。", deterministicCleanup: true, extraFilterWords: [], replacements: [],
            chineseScript: .simplified, chat: ("test-chat-model", chatURL, "chatURL-test"),
            chatContext: poemContext, session: session())
        XCTAssertEqual(text, "老板,帮我把鸟花拿过来。")
    }

    func testFailuresKeepTheDeterministicText() async {
        let deterministic = "锄禾日当午,观众有老虎。"
        for (status, body) in [(401, Data(#"{"error":"bad key"}"#.utf8)), (500, Data()), (503, Data("down".utf8)),
                               (200, Data("not json".utf8)), (200, reply("")),
                               (200, reply("好的！以下是修正后的文本，我还补充了整首诗的赏析：锄禾日当午，汗滴禾下土。谁知盘中餐，粒粒皆辛苦。"))] {
            StubURLProtocol.response = (status, body)
            let text = await TranscriptPostProcessor.apply(
                "出禾日当午,观众有老虎。", deterministicCleanup: true, extraFilterWords: [],
                replacements: [VocabularyReplacement(mishear: "出禾", correct: "锄禾")],
                chineseScript: .simplified, chat: ("test-chat-model", chatURL, "chatURL-test"),
                chatContext: poemContext, session: session())
            XCTAssertEqual(text, deterministic, "HTTP \(status)")
        }
    }

    func testUnreachableServerKeepsTheDeterministicText() async {
        let text = await TranscriptPostProcessor.apply(
            "出禾日当午", deterministicCleanup: true, extraFilterWords: [],
            replacements: [VocabularyReplacement(mishear: "出禾", correct: "锄禾")],
            chat: ("test-chat-model", "http://127.0.0.1:9/v1", "chatURL-test"), session: .shared)
        XCTAssertEqual(text, "锄禾日当午")
    }

    func testUnwrapsQuotesOnlyWhenTheTranscriptWasNotQuoted() {
        XCTAssertEqual(ChatCleanupClient.unwrap("「采菊东篱下」", original: "彩鞠动篱下"), "采菊东篱下")
        XCTAssertEqual(ChatCleanupClient.unwrap("「采菊东篱下」", original: "「彩鞠动篱下」"), "「采菊东篱下」")
        XCTAssertEqual(ChatCleanupClient.unwrap("```\n采菊东篱下\n```", original: "彩鞠动篱下"), "采菊东篱下")
        XCTAssertTrue(ChatCleanupClient.isPlausibleCorrection(original: "出禾", cleaned: "锄禾"))
        XCTAssertFalse(ChatCleanupClient.isPlausibleCorrection(original: "出禾", cleaned: ""))
    }
}
