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

    /// Mandarin sentence that steers Whisper to the chosen script with punctuation.
    public static func chinesePromptLead(_ script: ChineseScript) -> String {
        script == .traditional ? "以下是普通話的句子。" : "以下是普通话的句子。"
    }

    /// Whisper `prompt` for this language. Chinese gets a Mandarin lead (and terms in Chinese style)
    /// because an English prompt pulls zh audio toward English. Other languages use the glossary sentence.
    /// Terms come best first; the tail is dropped to stay within `maxTerms` and `tokenBudget`.
    public static func transcriptionPrompt(words: [String], language: String?,
                                           script: ChineseScript = .simplified,
                                           maxTerms: Int = 30, tokenBudget: Int = 224) -> String? {
        var terms = Array(words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.prefix(maxTerms))
        func build(_ terms: [String]) -> String? {
            guard ChineseScript.isChinese(language) else { return glossaryPrompt(from: terms) }
            let lead = chinesePromptLead(script)
            guard !terms.isEmpty else { return lead }
            return lead + "可能出现的词：" + terms.joined(separator: "、") + "。"
        }
        while !terms.isEmpty, let prompt = build(terms), estimatedTokens(prompt) > tokenBudget {
            terms.removeLast()
        }
        return build(terms)
    }

    /// Deliberately high token count for a Whisper prompt: each non-ASCII scalar counts as two
    /// tokens and ASCII text as one token per three characters.
    public static func estimatedTokens(_ text: String) -> Int {
        var ascii = 0
        var other = 0
        for scalar in text.unicodeScalars {
            if scalar.isASCII { ascii += 1 } else { other += 1 }
        }
        return other * 2 + (ascii + 2) / 3
    }

    /// Whisper repeats its prompt on near-silent audio. Drop that echo instead of pasting it.
    public static func stripPromptEcho(_ text: String, prompt: String?) -> String {
        guard let prompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty else {
            return text
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == prompt { return "" }
        if trimmed.hasPrefix(prompt) {
            return String(trimmed.dropFirst(prompt.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    public static func applyReplacements(_ text: String, _ replacements: [VocabularyReplacement]) -> String {
        let ordered = replacements
            .map { VocabularyReplacement(mishear: $0.mishear.trimmingCharacters(in: .whitespacesAndNewlines),
                                         correct: $0.correct.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.mishear.isEmpty }
            .sorted { $0.mishear.count > $1.mishear.count }
        var result = text
        for item in ordered {
            if let regex = wordRegex(for: item.mishear) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                let template = NSRegularExpression.escapedTemplate(for: item.correct)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: template)
            } else {
                result = result.replacingOccurrences(of: item.mishear, with: item.correct)
            }
        }
        return result
    }

    /// Same matching rule as `applyReplacements`: Latin words match whole and case-insensitively.
    public static func contains(_ term: String, in text: String) -> Bool {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !text.isEmpty else { return false }
        if let regex = wordRegex(for: term) {
            return regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) != nil
        }
        return text.contains(term)
    }

    private static func wordRegex(for term: String) -> NSRegularExpression? {
        guard term.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) && $0.isASCII }) else {
            return nil
        }
        let escaped = NSRegularExpression.escapedPattern(for: term)
        return try? NSRegularExpression(pattern: "(?i)(?<![A-Za-z0-9])\(escaped)(?![A-Za-z0-9])")
    }
}
