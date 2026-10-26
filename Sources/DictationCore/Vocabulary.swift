import Foundation

public struct VocabularyReplacement: Equatable, Codable, Sendable, Hashable {
    public var mishear: String
    public var correct: String

    public init(mishear: String, correct: String) {
        self.mishear = mishear
        self.correct = correct
    }
}

/// Custom terms for the Whisper `prompt`, plus an optional local mishear → correct table.
public enum Vocabulary {
    public static func parseWordList(_ raw: String) -> [String] {
        raw.split { $0 == "," || $0.isNewline || $0 == ";" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public static func parseReplacements(_ raw: String) -> [VocabularyReplacement] {
        raw.split(whereSeparator: \.isNewline).compactMap { line in
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !text.hasPrefix("#") else { return nil }
            let separator = text.contains("=>") ? "=>" : (text.contains("->") ? "->" : nil)
            guard let separator else { return nil }
            let parts = text.components(separatedBy: separator)
            guard parts.count >= 2 else { return nil }
            let mishear = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let correct = parts.dropFirst().joined(separator: separator)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !mishear.isEmpty, !correct.isEmpty else { return nil }
            return VocabularyReplacement(mishear: mishear, correct: correct)
        }
    }

    /// Glossary sentence, not a bare comma list — a noun list can poison Whisper into caption outros.
    public static func glossaryPrompt(from words: [String]) -> String? {
        let terms = words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !terms.isEmpty else { return nil }
        return "Voice dictation. Prefer these terms when they fit the speech: \(terms.joined(separator: ", "))."
    }

    public static func applyReplacements(_ text: String, _ replacements: [VocabularyReplacement]) -> String {
        let ordered = replacements
            .map { VocabularyReplacement(mishear: $0.mishear.trimmingCharacters(in: .whitespacesAndNewlines),
                                         correct: $0.correct.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.mishear.isEmpty }
            .sorted { $0.mishear.count > $1.mishear.count }
        var result = text
        for item in ordered {
            if item.mishear.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) && $0.isASCII }) {
                let escaped = NSRegularExpression.escapedPattern(for: item.mishear)
                let pattern = "(?i)(?<![A-Za-z0-9])\(escaped)(?![A-Za-z0-9])"
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(result.startIndex..<result.endIndex, in: result)
                    let template = NSRegularExpression.escapedTemplate(for: item.correct)
                    result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: template)
                }
            } else {
                result = result.replacingOccurrences(of: item.mishear, with: item.correct)
            }
        }
        return result
    }
}
