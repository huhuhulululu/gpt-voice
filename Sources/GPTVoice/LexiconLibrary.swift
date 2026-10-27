import DictationCore
import Foundation

/// The user's word list on disk. Lives beside history in Application Support; never synced.
@MainActor
final class LexiconLibrary: ObservableObject {
    @Published private(set) var lexicon: Lexicon
    @Published private(set) var errorMessage: String?
    let store: LexiconStore

    /// Seeds from the old Settings text fields only when no `lexicon.json` exists yet.
    init(fileURL: URL, legacyWords: String = "", legacyReplacements: String = "") {
        store = LexiconStore(fileURL: fileURL)
        switch store.load() {
        case .loaded(let saved):
            lexicon = saved
        case .missing:
            lexicon = Lexicon.migrating(words: legacyWords, replacements: legacyReplacements)
            if !lexicon.isEmpty { persist() }
        case .unreadable(let preserved):
            lexicon = Lexicon()
            errorMessage = preserved == nil
                ? "Could not read the word list."
                : "Could not read the word list. The old file was kept as \(preserved!.lastPathComponent)."
        }
    }

    nonisolated static func defaultFileURL(besides historyURL: URL) -> URL {
        historyURL.deletingLastPathComponent().appendingPathComponent("lexicon.json")
    }

    var terms: [LexiconTerm] { lexicon.terms }
    var replacements: [LexiconRule] { lexicon.replacements }
    var replacementList: [VocabularyReplacement] { lexicon.replacementList }

    func promptTerms(now: Date = Date()) -> Set<String> { Set(lexicon.promptTerms(now: now)) }

    func transcriptionPrompt(language: String?, script: ChineseScript) -> String? {
        lexicon.transcriptionPrompt(language: language, script: script)
    }

    /// Prompt terms plus the most used corrections, for the chat corrector.
    func chatContext(now: Date = Date()) -> ChatCleanupContext {
        let corrections = lexicon.replacements
            .sorted { ($0.hits, $0.lastUsed ?? $0.addedAt) > ($1.hits, $1.lastUsed ?? $1.addedAt) }
            .prefix(ChatCleanupContext.maxCorrections)
            .map(\.replacement)
        return ChatCleanupContext(terms: lexicon.promptTerms(now: now), corrections: Array(corrections))
    }

    @discardableResult
    func addTerm(_ text: String) -> Lexicon.Change {
        let change = lexicon.addTerm(text)
        if change != .invalid { persist() }
        return change
    }

    @discardableResult
    func addReplacement(mishear: String, correct: String) -> Lexicon.Change {
        let change = lexicon.addReplacement(mishear: mishear, correct: correct)
        if change != .invalid { persist() }
        return change
    }

    func removeTerm(id: UUID) {
        lexicon.removeTerm(id: id)
        persist()
    }

    func removeReplacement(id: UUID) {
        lexicon.removeReplacement(id: id)
        persist()
    }

    /// Called once per delivered transcript. Writes only when a term or rule was heard.
    func recordUsage(raw: String, delivered: String) {
        guard !lexicon.isEmpty, lexicon.recordUsage(raw: raw, delivered: delivered) else { return }
        persist()
    }

    private func persist() {
        do {
            try store.save(lexicon)
            errorMessage = nil
        } catch {
            errorMessage = "Could not save the word list. Changes apply until \(AppBrand.displayName) quits."
        }
    }
}
