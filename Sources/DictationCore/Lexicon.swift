import Foundation

/// A word the speaker uses. Terms only steer the Whisper `prompt`; they never rewrite text.
public struct LexiconTerm: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var text: String
    public var hits: Int
    public var addedAt: Date
    public var lastUsed: Date?

    public init(id: UUID = UUID(), text: String, hits: Int = 0, addedAt: Date, lastUsed: Date? = nil) {
        self.id = id
        self.text = text
        self.hits = hits
        self.addedAt = addedAt
        self.lastUsed = lastUsed
    }
}

/// A mishear → correct rule applied after transcription. Rules never enter the prompt.
public struct LexiconRule: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var mishear: String
    public var correct: String
    public var hits: Int
    public var addedAt: Date
    public var lastUsed: Date?

    public init(id: UUID = UUID(), mishear: String, correct: String, hits: Int = 0,
                addedAt: Date, lastUsed: Date? = nil) {
        self.id = id
        self.mishear = mishear
        self.correct = correct
        self.hits = hits
        self.addedAt = addedAt
        self.lastUsed = lastUsed
    }

    public var replacement: VocabularyReplacement { VocabularyReplacement(mishear: mishear, correct: correct) }
}

/// The user's local word list: prompt terms and replacement rules, kept apart.
public struct Lexicon: Codable, Equatable, Sendable {
    public enum Change: Equatable, Sendable {
        case added
        case updated
        case invalid
    }

    public static let currentVersion = 1
    /// Whisper reads at most 224 prompt tokens and keeps the tail, so an overlong prompt loses its lead.
    public static let promptTokenBudget = 224
    public static let maxPromptTerms = 30
    /// A term's weight halves for every two weeks it goes unheard.
    public static let halfLife: TimeInterval = 14 * 86_400
    /// Below this a term leaves the prompt. A new, never-heard term drops out after about seven weeks.
    public static let minimumPromptScore = 0.1
    public static let maxTermLength = 48

    public var version: Int
    public var terms: [LexiconTerm]
    public var replacements: [LexiconRule]

    public init(terms: [LexiconTerm] = [], replacements: [LexiconRule] = []) {
        version = Self.currentVersion
        self.terms = terms
        self.replacements = replacements
    }

    public var isEmpty: Bool { terms.isEmpty && replacements.isEmpty }
    public var replacementList: [VocabularyReplacement] { replacements.map(\.replacement) }

    // MARK: Editing

    @discardableResult
    public mutating func addTerm(_ raw: String, now: Date = Date()) -> Change {
        guard let text = Self.clean(raw) else { return .invalid }
        let key = Self.key(text)
        if let index = terms.firstIndex(where: { Self.key($0.text) == key }) {
            terms[index].text = text
            terms[index].hits += 1
            terms[index].lastUsed = now
            return .updated
        }
        terms.append(LexiconTerm(text: text, addedAt: now))
        return .added
    }

    /// Adding a mishear that already has a rule replaces its correction and refreshes it.
    @discardableResult
    public mutating func addReplacement(mishear rawMishear: String, correct rawCorrect: String,
                                        now: Date = Date()) -> Change {
        guard let mishear = Self.clean(rawMishear), let correct = Self.clean(rawCorrect),
              mishear != correct else { return .invalid }
        let key = Self.key(mishear)
        if let index = replacements.firstIndex(where: { Self.key($0.mishear) == key }) {
            replacements[index].mishear = mishear
            replacements[index].correct = correct
            replacements[index].hits += 1
            replacements[index].lastUsed = now
            return .updated
        }
        replacements.append(LexiconRule(mishear: mishear, correct: correct, addedAt: now))
        return .added
    }

    public mutating func removeTerm(id: UUID) { terms.removeAll { $0.id == id } }
    public mutating func removeReplacement(id: UUID) { replacements.removeAll { $0.id == id } }

    /// Counts a term when it appears in the delivered text, and a rule when its mishear
    /// appears in the raw transcript. Returns whether anything changed.
    @discardableResult
    public mutating func recordUsage(raw: String, delivered: String, now: Date = Date()) -> Bool {
        var changed = false
        for index in terms.indices where Vocabulary.contains(terms[index].text, in: delivered) {
            terms[index].hits += 1
            terms[index].lastUsed = now
            changed = true
        }
        for index in replacements.indices where Vocabulary.contains(replacements[index].mishear, in: raw) {
            replacements[index].hits += 1
            replacements[index].lastUsed = now
            changed = true
        }
        return changed
    }

    // MARK: Prompt

    /// Hits weighted by recency. A term added today scores 1 before it is ever heard.
    public static func score(_ term: LexiconTerm, now: Date) -> Double {
        let reference = term.lastUsed ?? term.addedAt
        let age = max(0, now.timeIntervalSince(reference))
        return Double(term.hits + 1) * pow(0.5, age / halfLife)
    }

    /// Terms that still earn a place in the prompt, best first.
    public func promptTerms(now: Date = Date(), limit: Int = Lexicon.maxPromptTerms) -> [String] {
        terms
            .map { (term: $0, score: Self.score($0, now: now)) }
            .filter { $0.score >= Self.minimumPromptScore }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.term.addedAt > rhs.term.addedAt
            }
            .prefix(limit)
            .map(\.term.text)
    }

    public func transcriptionPrompt(language: String?, script: ChineseScript = .simplified,
                                    context: String? = nil, now: Date = Date()) -> String? {
        Vocabulary.transcriptionPrompt(words: promptTerms(now: now), language: language, script: script,
                                       maxTerms: Self.maxPromptTerms, tokenBudget: Self.promptTokenBudget,
                                       context: context)
    }

    // MARK: Migration

    /// One-time import of the old comma list and `mishear => correct` lines.
    public static func migrating(words: String, replacements: String, now: Date = Date()) -> Lexicon {
        var lexicon = Lexicon()
        for word in Vocabulary.parseWordList(words)
        where !lexicon.terms.contains(where: { key($0.text) == key(word) }) {
            lexicon.addTerm(word, now: now)
        }
        for rule in Vocabulary.parseReplacements(replacements) {
            lexicon.addReplacement(mishear: rule.mishear, correct: rule.correct, now: now)
        }
        for index in lexicon.replacements.indices {
            lexicon.replacements[index].hits = 0
            lexicon.replacements[index].lastUsed = nil
        }
        return lexicon
    }

    // MARK: Helpers

    static func clean(_ raw: String) -> String? {
        let text = raw.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= maxTermLength else { return nil }
        return text
    }

    static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
    }
}
