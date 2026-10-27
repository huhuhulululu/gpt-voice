import AppKit
import DictationCore
import XCTest
@testable import GPTVoice

@MainActor
final class LexiconLibraryTests: XCTestCase {
    func testLegacyPreferencesSeedTheWordListOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("goice-lex-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("lexicon.json")
        let first = LexiconLibrary(fileURL: url, legacyWords: "Goice, Qwen", legacyReplacements: "go ice => Goice")
        XCTAssertEqual(first.terms.map(\.text), ["Goice", "Qwen"])
        first.removeTerm(id: first.terms[1].id)

        let reopened = LexiconLibrary(fileURL: url, legacyWords: "Goice, Qwen", legacyReplacements: "")
        XCTAssertEqual(reopened.terms.map(\.text), ["Goice"], "Saved list wins over the legacy strings")
        XCTAssertEqual(reopened.replacementList, [VocabularyReplacement(mishear: "go ice", correct: "Goice")])
    }

    func testNewCorrectionAppliesToTheNextDictationAndCountsHits() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("goice-lex-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = TranscriptionHistory(fileURL: directory.appendingPathComponent("history.json"))
        let suite = "goice-lex-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.automaticPaste = false
        let clipboard = NSPasteboard.withUniqueName()
        defer { clipboard.releaseGlobally() }
        let model = AppModel(preferences: preferences, pasteboard: clipboard, history: history) { _ in
            "Open go ice now."
        }
        defer { model.cleanup() }
        XCTAssertEqual(model.lexicon.store.fileURL, directory.appendingPathComponent("lexicon.json"))

        model.transcribeFile(URL(fileURLWithPath: "/first.wav"))
        try await waitUntil { model.phase == .finished(.copied(.automaticPasteOff)) }
        XCTAssertEqual(model.lastTranscript, "Open go ice now.")

        XCTAssertEqual(model.lexicon.addReplacement(mishear: "go ice", correct: "Goice"), .added)
        model.lexicon.addTerm("Goice")
        model.transcribeFile(URL(fileURLWithPath: "/second.wav"))
        try await waitUntil { model.phase == .finished(.copied(.automaticPasteOff)) && model.lastTranscript != "Open go ice now." }
        XCTAssertEqual(model.lastTranscript, "Open Goice now.")
        XCTAssertEqual(model.lexicon.replacements.first?.hits, 1)
        XCTAssertEqual(model.lexicon.terms.first?.hits, 1)
        guard case .loaded(let saved) = model.lexicon.store.load() else { return XCTFail("Expected a saved list") }
        XCTAssertEqual(saved.replacements.first?.hits, 1)
    }

    func testHistoryCorrectionOfTheLiveSampleFixesTheNextDictation() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("goice-lex-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = TranscriptionHistory(fileURL: directory.appendingPathComponent("history.json"))
        let suite = "goice-lex-zh-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.automaticPaste = false
        let clipboard = NSPasteboard.withUniqueName()
        defer { clipboard.releaseGlobally() }
        let model = AppModel(preferences: preferences, pasteboard: clipboard, history: history) { _ in
            "彩鞠动篱下,悠然见南山。"
        }
        defer { model.cleanup() }

        model.transcribeFile(URL(fileURLWithPath: "/first.wav"))
        try await waitUntil { model.phase == .finished(.copied(.automaticPasteOff)) }
        await history.waitForPendingChanges()
        let heard = try XCTUnwrap(history.entries.first?.text)
        XCTAssertEqual(model.lexicon.addReplacement(mishear: heard, correct: "采菊东篱下，悠然见南山。"), .added)

        model.transcribeFile(URL(fileURLWithPath: "/second.wav"))
        try await waitUntil { model.lastTranscript == "采菊东篱下，悠然见南山。" && model.phase == .finished(.copied(.automaticPasteOff)) }
        XCTAssertEqual(model.lexicon.replacements.first?.hits, 1)
        guard case .loaded(let saved) = model.lexicon.store.load() else { return XCTFail("Expected a saved list") }
        XCTAssertEqual(saved.replacements.first?.hits, 1)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let limit = Date().addingTimeInterval(3)
        while !condition(), Date() < limit { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(condition())
    }
}
