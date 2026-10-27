import XCTest
@testable import DictationCore

final class TranscriptCleanupTests: XCTestCase {
    func testStripsFillersAndNormalizesSpaces() {
        let cleaned = TranscriptCleanup.apply("Um, hello  uh  world.")
        XCTAssertEqual(cleaned, "hello world.")
    }

    func testStripsChineseFillers() {
        XCTAssertEqual(TranscriptCleanup.apply("嗯 你好 呃 世界"), "你好世界")
        XCTAssertEqual(TranscriptCleanup.apply("嗯，我觉得可以。"), "我觉得可以。")
        XCTAssertEqual(TranscriptCleanup.apply("你好，呃，世界。"), "你好，世界。")
        XCTAssertEqual(TranscriptCleanup.apply("嗯嗯，好的，嗯。"), "好的。")
    }

    func testKeepsChineseWordsThatContainFillerCharacters() {
        let text = "金额是三百元，额外的费用和名额另算。"
        XCTAssertEqual(TranscriptCleanup.apply(text), text)
        XCTAssertEqual(TranscriptCleanup.apply("额度用完了"), "额度用完了")
    }

    func testRemovesSpacesBetweenChineseCharactersOnly() {
        XCTAssertEqual(TranscriptCleanup.apply("测试 测试 测试"), "测试测试测试")
        XCTAssertEqual(TranscriptCleanup.apply("使用 Goice 软件 ， 很方便"), "使用 Goice 软件，很方便")
    }

    func testKeepsDecimalsVersionsAndDomains() {
        let text = "Version 3.14 at example.com costs 12,000 yen, v1.2 ships."
        XCTAssertEqual(TranscriptCleanup.apply(text), text)
    }

    func testPrunesTrailingWhisperHallucination() {
        XCTAssertEqual(TranscriptCleanup.apply("Take a left. Thanks for watching."), "Take a left.")
        XCTAssertEqual(TranscriptCleanup.apply("Thanks for watching."), "")
        XCTAssertEqual(TranscriptCleanup.apply("谢谢观看"), "")
        XCTAssertEqual(TranscriptCleanup.apply("测试测试测试。谢谢观看。"), "测试测试测试。")
        XCTAssertEqual(TranscriptCleanup.apply("字幕由Amara.org社区提供"), "")
        XCTAssertEqual(TranscriptCleanup.apply("Please subscribe"), "")
    }

    func testGenericThanksIsRemovedOnlyAsTheWholeTranscript() {
        XCTAssertEqual(TranscriptCleanup.apply("Thank you."), "")
        XCTAssertEqual(TranscriptCleanup.apply("you"), "")
        XCTAssertEqual(TranscriptCleanup.apply("Please send it by Friday. Thank you."),
                       "Please send it by Friday. Thank you.")
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

    func testChinesePromptUsesAMandarinLeadAndChineseStyleTerms() {
        XCTAssertEqual(Vocabulary.transcriptionPrompt(words: [], language: "zh"), "以下是普通话的句子。")
        XCTAssertEqual(Vocabulary.transcriptionPrompt(words: ["Goice", "声笔"], language: "zh"),
                       "以下是普通话的句子。可能出现的词：Goice、声笔。")
        XCTAssertEqual(Vocabulary.transcriptionPrompt(words: [], language: "zh", script: .traditional),
                       "以下是普通話的句子。")
        XCTAssertEqual(Vocabulary.transcriptionPrompt(words: ["Goice"], language: "en"),
                       "Voice dictation. Prefer these terms when they fit the speech: Goice.")
        XCTAssertNil(Vocabulary.transcriptionPrompt(words: [], language: nil))
    }

    func testPromptEchoIsDropped() {
        let prompt = "以下是普通话的句子。"
        XCTAssertEqual(Vocabulary.stripPromptEcho("以下是普通话的句子。", prompt: prompt), "")
        XCTAssertEqual(Vocabulary.stripPromptEcho("以下是普通话的句子。测试测试测试", prompt: prompt), "测试测试测试")
        XCTAssertEqual(Vocabulary.stripPromptEcho("测试测试测试", prompt: prompt), "测试测试测试")
    }

    func testChineseScriptConversion() {
        XCTAssertEqual(ChineseScript.simplified.convert("測試測試測試"), "测试测试测试")
        XCTAssertEqual(ChineseScript.traditional.convert("测试"), "測試")
        XCTAssertEqual(ChineseScript.unchanged.convert("測試"), "測試")
        XCTAssertTrue(ChineseScript.isChinese("zh"))
        XCTAssertTrue(ChineseScript.isChinese("zh-CN"))
        XCTAssertFalse(ChineseScript.isChinese("en"))
        XCTAssertFalse(ChineseScript.isChinese(nil))
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
        XCTAssertEqual(result, "take a right. Thank you.")
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.path, "/v1/chat/completions")
    }

    func testPromptEchoAndScriptAreHandledBeforeCleanup() async {
        let session = URLSession(configuration: .ephemeral)
        let echo = await TranscriptPostProcessor.apply(
            "以下是普通话的句子。", deterministicCleanup: true, extraFilterWords: [], replacements: [],
            chineseScript: .simplified, prompt: "以下是普通话的句子。", chat: nil, session: session)
        XCTAssertEqual(echo, "")
        let traditional = await TranscriptPostProcessor.apply(
            "測試 測試 測試", deterministicCleanup: true, extraFilterWords: [], replacements: [],
            chineseScript: .simplified, prompt: nil, chat: nil, session: session)
        XCTAssertEqual(traditional, "测试测试测试")
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
        XCTAssertEqual(store.readSecret(for: KeychainSecretStore.apiKeyAccount), .value("sk-test"))
        XCTAssertTrue(store.containsSecret(for: KeychainSecretStore.apiKeyAccount))
        try store.setSecret("", for: KeychainSecretStore.apiKeyAccount)
        XCTAssertNil(store.secret(for: KeychainSecretStore.apiKeyAccount))
        XCTAssertEqual(store.readSecret(for: KeychainSecretStore.apiKeyAccount), .missing)
        XCTAssertFalse(store.containsSecret(for: KeychainSecretStore.apiKeyAccount))
    }
}
