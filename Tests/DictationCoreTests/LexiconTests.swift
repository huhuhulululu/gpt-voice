import DictationCore
import XCTest

final class LexiconTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testTermsAndReplacementsStaySeparate() {
        var lexicon = Lexicon()
        XCTAssertEqual(lexicon.addTerm("Goice", now: now), .added)
        XCTAssertEqual(lexicon.addReplacement(mishear: "go ice", correct: "Goice", now: now), .added)
        XCTAssertEqual(lexicon.terms.map(\.text), ["Goice"])
        XCTAssertEqual(lexicon.replacementList, [VocabularyReplacement(mishear: "go ice", correct: "Goice")])
        XCTAssertEqual(lexicon.promptTerms(now: now), ["Goice"])
    }

    func testAddingAgainDeduplicatesAndCountsAHit() {
        var lexicon = Lexicon()
        lexicon.addTerm("Qwen", now: now)
        XCTAssertEqual(lexicon.addTerm("  qwen ", now: now), .updated)
        XCTAssertEqual(lexicon.terms.count, 1)
        XCTAssertEqual(lexicon.terms[0].hits, 1)

        lexicon.addReplacement(mishear: "千问", correct: "Qwen", now: now)
        XCTAssertEqual(lexicon.addReplacement(mishear: "千问", correct: "通义千问", now: now), .updated)
        XCTAssertEqual(lexicon.replacements.count, 1)
        XCTAssertEqual(lexicon.replacements[0].correct, "通义千问")
        XCTAssertEqual(lexicon.replacements[0].hits, 1)
    }

    func testRejectsEmptyIdenticalOrOverlongEntries() {
        var lexicon = Lexicon()
        XCTAssertEqual(lexicon.addTerm("   ", now: now), .invalid)
        XCTAssertEqual(lexicon.addTerm(String(repeating: "a", count: Lexicon.maxTermLength + 1), now: now), .invalid)
        XCTAssertEqual(lexicon.addReplacement(mishear: "Goice", correct: " Goice ", now: now), .invalid)
        XCTAssertEqual(lexicon.addReplacement(mishear: "", correct: "Goice", now: now), .invalid)
        XCTAssertTrue(lexicon.isEmpty)
    }

    func testRecordUsageCountsTermsInDeliveredTextAndRulesInRawText() {
        var lexicon = Lexicon()
        lexicon.addTerm("Goice", now: now)
        lexicon.addTerm("Codex", now: now)
        lexicon.addReplacement(mishear: "go ice", correct: "Goice", now: now)
        let later = now.addingTimeInterval(60)
        XCTAssertTrue(lexicon.recordUsage(raw: "open go ice now", delivered: "open Goice now", now: later))
        XCTAssertEqual(lexicon.terms.first { $0.text == "Goice" }?.hits, 1)
        XCTAssertEqual(lexicon.terms.first { $0.text == "Goice" }?.lastUsed, later)
        XCTAssertEqual(lexicon.terms.first { $0.text == "Codex" }?.hits, 0)
        XCTAssertEqual(lexicon.replacements[0].hits, 1)
        XCTAssertFalse(lexicon.recordUsage(raw: "nothing", delivered: "nothing", now: later))
    }

    func testLatinTermsMatchWholeWordsOnly() {
        XCTAssertTrue(Vocabulary.contains("Codex", in: "ask codex."))
        XCTAssertFalse(Vocabulary.contains("Codex", in: "Codexes"))
        XCTAssertTrue(Vocabulary.contains("声笔", in: "打开声笔吧"))
    }

    func testRankingPrefersFrequentRecentTermsAndDropsStaleOnes() {
        var lexicon = Lexicon()
        lexicon.terms = [
            LexiconTerm(text: "stale", hits: 0, addedAt: now.addingTimeInterval(-90 * day)),
            LexiconTerm(text: "fresh", hits: 0, addedAt: now),
            LexiconTerm(text: "frequent", hits: 9, addedAt: now.addingTimeInterval(-60 * day),
                        lastUsed: now.addingTimeInterval(-7 * day)),
            LexiconTerm(text: "oldHits", hits: 9, addedAt: now.addingTimeInterval(-200 * day),
                        lastUsed: now.addingTimeInterval(-150 * day)),
        ]
        XCTAssertEqual(lexicon.promptTerms(now: now), ["frequent", "fresh"])
    }

    func testPromptKeepsAtMostThirtyTerms() {
        var lexicon = Lexicon()
        for index in 0..<45 { lexicon.addTerm("t\(index)", now: now.addingTimeInterval(Double(index))) }
        XCTAssertEqual(lexicon.promptTerms(now: now.addingTimeInterval(100)).count, Lexicon.maxPromptTerms)
    }

    func testPromptStaysWithinTheTokenBudgetAndKeepsTheLead() throws {
        var lexicon = Lexicon()
        for index in 0..<30 {
            lexicon.addTerm("超长专有名词测试第\(index)号", now: now.addingTimeInterval(Double(index)))
        }
        let prompt = try XCTUnwrap(lexicon.transcriptionPrompt(language: "zh", now: now.addingTimeInterval(100)))
        XCTAssertLessThanOrEqual(Vocabulary.estimatedTokens(prompt), Lexicon.promptTokenBudget)
        XCTAssertTrue(prompt.hasPrefix("以下是普通话的句子。可能出现的词："))
        XCTAssertTrue(prompt.contains("超长专有名词测试第29号"), "Best-ranked terms survive the cut")

        let english = try XCTUnwrap(Vocabulary.transcriptionPrompt(
            words: (0..<200).map { "Term\($0)" }, language: "en", maxTerms: 200))
        XCTAssertLessThanOrEqual(Vocabulary.estimatedTokens(english), Lexicon.promptTokenBudget)
    }

    func testMigrationImportsLegacyStringsWithoutHits() {
        let lexicon = Lexicon.migrating(words: "Goice, Qwen\ngoice", replacements: "go ice => Goice\n# note\nbad line",
                                        now: now)
        XCTAssertEqual(lexicon.terms.map(\.text), ["Goice", "Qwen"])
        XCTAssertEqual(lexicon.terms.map(\.hits), [0, 0])
        XCTAssertEqual(lexicon.replacementList, [VocabularyReplacement(mishear: "go ice", correct: "Goice")])
    }

    func testStoreRoundTripsAndPreservesAnUnreadableFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("goice-lexicon-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LexiconStore(fileURL: directory.appendingPathComponent("lexicon.json"))
        XCTAssertEqual(store.load(), .missing)

        var lexicon = Lexicon()
        lexicon.addTerm("Goice", now: now)
        lexicon.addReplacement(mishear: "go ice", correct: "Goice", now: now)
        try store.save(lexicon)
        XCTAssertEqual(store.load(), .loaded(lexicon))
        lexicon.addTerm("Qwen", now: now)
        try store.save(lexicon)
        XCTAssertEqual(store.load(), .loaded(lexicon))

        try Data("not json".utf8).write(to: store.fileURL)
        guard case .unreadable(let preserved?) = store.load() else { return XCTFail("Expected unreadable") }
        XCTAssertEqual(try String(contentsOf: preserved, encoding: .utf8), "not json")
        XCTAssertEqual(store.load(), .missing)
    }
}
