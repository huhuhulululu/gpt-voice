import XCTest
@testable import DictationCore

final class TranscriptCleanupTests: XCTestCase {
    func testStripsFillersAndNormalizesSpaces() {
        let cleaned = TranscriptCleanup.apply("Um, hello  uh  world.")
        XCTAssertEqual(cleaned, "hello world.")
    }

    func testStripsChineseFillers() {
        let cleaned = TranscriptCleanup.apply("嗯 你好 呃 世界")
        XCTAssertEqual(cleaned, "你好 世界")
    }

    func testPrunesTrailingWhisperHallucination() {
        XCTAssertEqual(TranscriptCleanup.apply("Take a left. Thank you."), "Take a left.")
        XCTAssertEqual(TranscriptCleanup.apply("Thanks for watching."), "")
        XCTAssertEqual(TranscriptCleanup.apply("谢谢观看"), "")
        XCTAssertEqual(TranscriptCleanup.apply("Please subscribe"), "")
    }

    func testKeepsThankYouMidSentence() {
        let cleaned = TranscriptCleanup.apply("Thank you for the tea.")
        XCTAssertEqual(cleaned, "Thank you for the tea.")
    }

    func testStripsBlankAudioMarker() {
        XCTAssertEqual(TranscriptCleanup.apply("[BLANK_AUDIO]"), "")
    }

    func testCustomFilterWords() {
        let cleaned = TranscriptCleanup.apply("Hello kinda world", filterWords: ["kinda"], endPrunePhrases: [])
        XCTAssertEqual(cleaned, "Hello world")
    }
}

final class VocabularyTests: XCTestCase {
    func testGlossaryPromptIsASentenceNotABareList() {
        let prompt = Vocabulary.glossaryPrompt(from: ["Goice", "Qwen"])
        XCTAssertEqual(prompt, "Voice dictation. Prefer these terms when they fit the speech: Goice, Qwen.")
        XCTAssertNil(Vocabulary.glossaryPrompt(from: ["  "]))
    }

    func testReplacementUsesWordBoundaries() {
        let table = [VocabularyReplacement(mishear: "go ice", correct: "Goice")]
        XCTAssertEqual(Vocabulary.applyReplacements("Use go ice today", table), "Use Goice today")
        XCTAssertEqual(Vocabulary.applyReplacements("ongoing ice", table), "ongoing ice")
    }

    func testParsesReplacementLines() {
        let parsed = Vocabulary.parseReplacements("go ice => Goice\n# comment\nbad -> good\n")
        XCTAssertEqual(parsed, [
            VocabularyReplacement(mishear: "go ice", correct: "Goice"),
            VocabularyReplacement(mishear: "bad", correct: "good")
        ])
    }
}

final class TranscriptPostProcessorTests: XCTestCase {
    func testChatFailureFallsBackToDeterministicCleanup() async {
        StubURLProtocol.reset()
        StubURLProtocol.response = (500, Data(#"{"error":"nope"}"#.utf8))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        let result = await TranscriptPostProcessor.apply(
            "Um, take a left. Thank you.",
            deterministicCleanup: true,
            extraFilterWords: [],
            replacements: [VocabularyReplacement(mishear: "left", correct: "right")],
            chat: (model: "gpt-4o-mini", baseURL: "https://api.openai.com/v1", apiKey: "sk-test"),
            session: session
        )
        XCTAssertEqual(result, "take a right.")
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.path, "/v1/chat/completions")
    }

    func testChatSuccessReplacesDeterministicText() async {
        StubURLProtocol.reset()
        StubURLProtocol.response = (200, Data(#"{"choices":[{"message":{"content":"Take a left."}}]}"#.utf8))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        let result = await TranscriptPostProcessor.apply(
            "Um, take a left.",
            deterministicCleanup: true,
            extraFilterWords: [],
            replacements: [],
            chat: (model: "gpt-4o-mini", baseURL: "https://api.openai.com/v1", apiKey: "sk-test"),
            session: session
        )
        XCTAssertEqual(result, "Take a left.")
    }
}

final class SecretStoreTests: XCTestCase {
    func testMemoryStoreDoesNotKeepEmptySecrets() throws {
        let store = MemorySecretStore()
        try store.setSecret("sk-test", for: KeychainSecretStore.apiKeyAccount)
        XCTAssertEqual(store.secret(for: KeychainSecretStore.apiKeyAccount), "sk-test")
        try store.setSecret("", for: KeychainSecretStore.apiKeyAccount)
        XCTAssertNil(store.secret(for: KeychainSecretStore.apiKeyAccount))
    }
}
