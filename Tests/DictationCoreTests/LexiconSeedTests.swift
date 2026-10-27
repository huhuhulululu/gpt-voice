import XCTest
@testable import DictationCore

final class LexiconSeedTests: XCTestCase {
    private func retestLexicon() throws -> Lexicon {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/retest-lexicon-seed.json")
        let seed = try JSONDecoder().decode(LexiconSeed.self, from: Data(contentsOf: url))
        var lexicon = Lexicon()
        lexicon.addReplacement(mishear: "出合", correct: "锄禾")
        let added = lexicon.merge(seed)
        XCTAssertEqual(added.terms, 3)
        XCTAssertEqual(added.corrections, 7)
        XCTAssertEqual(lexicon.merge(seed).corrections, 0, "Merging twice adds nothing")
        return lexicon
    }

    func testSeededCorrectionsRescueTheRecordedMishears() throws {
        let rules = try retestLexicon().replacementList
        let samples = [
            "出禾日当午,汗滴禾下土," : "锄禾日当午,汗滴禾下土,",
            "出盒日当午,观众有老虎。" : "锄禾日当午,观众有老虎。",
            "出河日当午,关中有老虎。" : "锄禾日当午,关中有老虎。",
            "出合日当午" : "锄禾日当午",
            "出禾" : "锄禾",
            "彩鞠动篱下,悠然见南山。" : "采菊东篱下,悠然见南山。",
            "谁知盘中餐、粒粒皆辛苦。" : "谁知盘中餐、粒粒皆辛苦。",
            "出门买菜" : "出门买菜",
        ]
        for (heard, expected) in samples {
            XCTAssertEqual(Vocabulary.applyReplacements(heard, rules), expected, heard)
        }
    }

    func testSeededTermsGoIntoThePromptOnly() throws {
        let lexicon = try retestLexicon()
        let prompt = try XCTUnwrap(lexicon.transcriptionPrompt(language: "zh"))
        for term in ["锄禾日当午", "采菊东篱下", "悠然见南山"] { XCTAssertTrue(prompt.contains(term)) }
        XCTAssertFalse(lexicon.replacements.contains { $0.mishear == "悠然见南山" })
    }

    func testLiveSampleThroughThePostProcessorCountsTheRuleHit() async throws {
        var lexicon = try retestLexicon()
        let session = URLSession(configuration: .ephemeral)
        let processed = await TranscriptPostProcessor.applyReporting(
            "彩鞠动篱下,悠然见南山。", deterministicCleanup: true, extraFilterWords: [],
            replacements: lexicon.replacementList, chineseScript: .simplified, chat: nil, session: session)
        XCTAssertTrue(processed.text.hasPrefix("采菊东篱下"), processed.text)
        XCTAssertTrue(processed.text.hasSuffix("悠然见南山。"), processed.text)
        XCTAssertTrue(lexicon.recordUsage(raw: processed.beforeReplacements, delivered: processed.text))
        XCTAssertEqual(lexicon.replacements.first { $0.mishear == "彩鞠动篱下" }?.hits, 1)
        XCTAssertEqual(lexicon.terms.first { $0.text == "采菊东篱下" }?.hits, 1)
        XCTAssertEqual(lexicon.terms.first { $0.text == "悠然见南山" }?.hits, 1)
    }

    /// A whole sentence copied from History is matched against cleaned text, not the raw STT text.
    func testWholeSentenceCorrectionFromHistoryHitsAfterCleanup() async throws {
        let session = URLSession(configuration: .ephemeral)
        let first = await TranscriptPostProcessor.applyReporting(
            "嗯 彩鞠动篱下,悠然见南山。", deterministicCleanup: true, extraFilterWords: [], replacements: [],
            chineseScript: .simplified, chat: nil, session: session)
        var lexicon = Lexicon()
        XCTAssertEqual(lexicon.addReplacement(mishear: first.text, correct: "采菊东篱下，悠然见南山。"), .added)
        let next = await TranscriptPostProcessor.applyReporting(
            "嗯 彩鞠动篱下,悠然见南山。", deterministicCleanup: true, extraFilterWords: [],
            replacements: lexicon.replacementList, chineseScript: .simplified, chat: nil, session: session)
        XCTAssertEqual(next.text, "采菊东篱下，悠然见南山。")
        XCTAssertTrue(lexicon.recordUsage(raw: next.beforeReplacements, delivered: next.text))
        XCTAssertEqual(lexicon.replacements[0].hits, 1)
    }
}
