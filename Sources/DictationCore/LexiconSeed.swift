import Foundation

/// A hand-written list to merge into the word list: `{"terms": [...], "corrections": [{"heard": "", "correct": ""}]}`.
public struct LexiconSeed: Decodable, Equatable, Sendable {
    public struct Correction: Decodable, Equatable, Sendable {
        public var heard: String
        public var correct: String

        public init(heard: String, correct: String) {
            self.heard = heard
            self.correct = correct
        }
    }

    public var terms: [String]
    public var corrections: [Correction]

    public init(terms: [String] = [], corrections: [Correction] = []) {
        self.terms = terms
        self.corrections = corrections
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        terms = try container.decodeIfPresent([String].self, forKey: .terms) ?? []
        corrections = try container.decodeIfPresent([Correction].self, forKey: .corrections) ?? []
    }

    private enum CodingKeys: String, CodingKey { case terms, corrections }
}

extension Lexicon {
    /// Adds seed entries without counting them as heard. Existing corrections take the seed's fix.
    /// Returns how many entries were new.
    @discardableResult
    public mutating func merge(_ seed: LexiconSeed, now: Date = Date()) -> (terms: Int, corrections: Int) {
        var added = (terms: 0, corrections: 0)
        for raw in seed.terms {
            guard let text = Self.clean(raw) else { continue }
            if terms.contains(where: { Self.key($0.text) == Self.key(text) }) { continue }
            terms.append(LexiconTerm(text: text, addedAt: now))
            added.terms += 1
        }
        for rule in seed.corrections {
            guard let mishear = Self.clean(rule.heard), let correct = Self.clean(rule.correct),
                  mishear != correct else { continue }
            if let index = replacements.firstIndex(where: { Self.key($0.mishear) == Self.key(mishear) }) {
                replacements[index].correct = correct
            } else {
                replacements.append(LexiconRule(mishear: mishear, correct: correct, addedAt: now))
                added.corrections += 1
            }
        }
        return added
    }
}
