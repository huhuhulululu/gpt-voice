import XCTest
@testable import DictationCore

final class PromptContinuationTests: XCTestCase {
    func testChinesePromptEndsWithThePreviousDictation() {
        let prompt = Vocabulary.transcriptionPrompt(words: ["锄禾日当午", "采菊东篱下"], language: "zh",
                                                    context: "锄禾日当午，汗滴禾下土。")
        XCTAssertEqual(prompt, "以下是普通话的句子。可能出现的词：锄禾日当午、采菊东篱下。锄禾日当午，汗滴禾下土。")
        XCTAssertEqual(Vocabulary.transcriptionPrompt(words: [], language: "zh", context: "好的。"),
                       "以下是普通话的句子。好的。")
    }

    func testOtherLanguagesAppendContextAfterTheGlossary() {
        XCTAssertEqual(Vocabulary.transcriptionPrompt(words: ["Goice"], language: "en", context: "Ship it today."),
                       "Voice dictation. Prefer these terms when they fit the speech: Goice. Ship it today.")
        XCTAssertEqual(Vocabulary.transcriptionPrompt(words: [], language: nil, context: "Ship it today."),
                       "Ship it today.")
        XCTAssertNil(Vocabulary.transcriptionPrompt(words: [], language: nil, context: "   "))
    }

    func testContextKeepsTheLastClauseWithinTheLimit() {
        let long = "今天先把发布说明写完，然后检查一下签名流程，最后把锄禾日当午这一句重新测试一遍。"
        let tail = Vocabulary.continuationContext(long, chinese: true)
        XCTAssertEqual(tail, "最后把锄禾日当午这一句重新测试一遍。")
        XCTAssertLessThanOrEqual(tail?.count ?? 0, Vocabulary.continuationCharacters.chinese)
        let english = String(repeating: "word ", count: 40) + "and the final sentence ends here."
        let englishTail = Vocabulary.continuationContext(english, chinese: false) ?? ""
        XCTAssertTrue(englishTail.hasSuffix("ends here."))
        XCTAssertFalse(englishTail.hasPrefix(" "))
        XCTAssertLessThanOrEqual(englishTail.count, Vocabulary.continuationCharacters.other)
    }

    func testTermsWinOverContextWhenTheBudgetIsTight() {
        let terms = (0..<30).map { "术语词条\($0)号" }
        let prompt = Vocabulary.transcriptionPrompt(words: terms, language: "zh", context: "上一句话的结尾。") ?? ""
        XCTAssertFalse(prompt.contains("上一句话的结尾"))
        XCTAssertLessThanOrEqual(Vocabulary.estimatedTokens(prompt), Lexicon.promptTokenBudget)
        XCTAssertTrue(prompt.contains("术语词条0号"))

        let few = Vocabulary.transcriptionPrompt(words: Array(terms.prefix(3)), language: "zh", context: "上一句话的结尾。")
        XCTAssertTrue(few?.hasSuffix("上一句话的结尾。") == true)
    }

    func testLexiconPassesContextThrough() {
        var lexicon = Lexicon()
        lexicon.addTerm("采菊东篱下")
        XCTAssertEqual(lexicon.transcriptionPrompt(language: "zh", context: "锄禾日当午。"),
                       "以下是普通话的句子。可能出现的词：采菊东篱下。锄禾日当午。")
    }

    func testWholePromptEchoWithContextIsDropped() async {
        let prompt = Vocabulary.transcriptionPrompt(words: ["采菊东篱下"], language: "zh", context: "好的。")
        let text = await TranscriptPostProcessor.apply(prompt ?? "", deterministicCleanup: true, extraFilterWords: [],
                                                       replacements: [], prompt: prompt, chat: nil, session: .shared)
        XCTAssertEqual(text, "")
    }
}

final class ChinesePunctuationTests: XCTestCase {
    private func clean(_ text: String) -> String { TranscriptCleanup.apply(text) }

    func testASCIIPunctuationAfterHanBecomesChinese() {
        XCTAssertEqual(clean("老板,帮我把鸟花拿过来."), "老板，帮我把鸟花拿过来。")
        XCTAssertEqual(clean("你好吗? 我很好!"), "你好吗？我很好！")
        XCTAssertEqual(clean("注意;这里:重点"), "注意；这里：重点")
        XCTAssertEqual(clean("然后呢..."), "然后呢……")
    }

    func testSpacingAndDoublesAroundChinesePunctuation() {
        XCTAssertEqual(clean("锄禾日当午 ， 汗滴禾下土 。"), "锄禾日当午，汗滴禾下土。")
        XCTAssertEqual(clean("好的。。"), "好的。")
        XCTAssertEqual(clean("好的，，可以"), "好的，可以")
        XCTAssertEqual(clean("「 采菊东篱下 」"), "「采菊东篱下」")
    }

    func testFullwidthLettersAndDigitsBecomeASCII() {
        XCTAssertEqual(clean("版本ＧＰＴ５，第１２３号"), "版本GPT5，第123号")
    }

    func testNumbersVersionsAndEnglishAreLeftAlone() {
        XCTAssertEqual(clean("圆周率是3.14,版本v1.2"), "圆周率是3.14,版本v1.2")
        XCTAssertEqual(clean("会议12:30开始"), "会议12:30开始")
        XCTAssertEqual(clean("时间:12:30"), "时间:12:30")
        XCTAssertEqual(clean("Hello, world. Ship it!"), "Hello, world. Ship it!")
        XCTAssertEqual(clean("用Swift,然后测试"), "用Swift,然后测试")
        XCTAssertEqual(clean("これは日本語です,はい"), "これは日本語です,はい")
    }

    func testOldRulesWithASCIICommasStillMatch() {
        let rule = VocabularyReplacement(mishear: "彩鞠动篱下,悠然", correct: "采菊东篱下，悠然")
        XCTAssertEqual(Vocabulary.applyReplacements(clean("彩鞠动篱下,悠然见南山。"), [rule]), "采菊东篱下，悠然见南山。")
        XCTAssertTrue(Vocabulary.contains("彩鞠动篱下,悠然", in: "彩鞠动篱下，悠然见南山。"))
    }
}
