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
    /// `context` is the end of the previous dictation. Whisper reads the prompt as the text just before
    /// the audio, so it goes last; it is the first thing dropped when the budget is tight.
    public static func transcriptionPrompt(words: [String], language: String?,
                                           script: ChineseScript = .simplified,
                                           maxTerms: Int = 30, tokenBudget: Int = 224,
                                           context: String? = nil) -> String? {
        let chinese = ChineseScript.isChinese(language)
        var terms = Array(words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.prefix(maxTerms))
        var context = context.flatMap { continuationContext($0, chinese: chinese) }
        func build(_ terms: [String]) -> String? {
            let base: String?
            if chinese {
                let lead = chinesePromptLead(script)
                base = terms.isEmpty ? lead : lead + "可能出现的词：" + terms.joined(separator: "、") + "。"
            } else {
                base = glossaryPrompt(from: terms)
            }
            guard let context else { return base }
            guard let base else { return context }
            return chinese ? base + context : base + " " + context
        }
        if context != nil, let prompt = build(terms), estimatedTokens(prompt) > tokenBudget { context = nil }
        while !terms.isEmpty, let prompt = build(terms), estimatedTokens(prompt) > tokenBudget {
            terms.removeLast()
        }
        return build(terms)
    }

    public static let continuationCharacters = (chinese: 24, other: 120)

    /// The last clause or sentence of a dictation, short enough to leave room for terms.
    public static func continuationContext(_ text: String, chinese: Bool) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let limit = chinese ? continuationCharacters.chinese : continuationCharacters.other
        guard trimmed.count > limit else { return trimmed }
        var tail = Substring(trimmed.suffix(limit))
        if let boundary = tail.dropLast().firstIndex(where: { "。！？；，、,.!?;".contains($0) }) {
            tail = tail[tail.index(after: boundary)...]
        } else if !chinese, let space = tail.firstIndex(of: " ") {
            tail = tail[tail.index(after: space)...]
        }
        let result = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
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

    /// Mishears are also matched in their punctuation-normalized form, so a rule copied before
    /// Chinese punctuation was normalized (`老板,帮我`) still matches `老板，帮我`.
    public static func applyReplacements(_ text: String, _ replacements: [VocabularyReplacement]) -> String {
        let ordered = replacements
            .map { VocabularyReplacement(mishear: $0.mishear.trimmingCharacters(in: .whitespacesAndNewlines),
                                         correct: $0.correct.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.mishear.isEmpty }
            .flatMap { item in
                matchVariants(item.mishear).map { VocabularyReplacement(mishear: $0, correct: item.correct) }
            }
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
        return matchVariants(term).contains { variant in
            if let regex = wordRegex(for: variant) {
                return regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) != nil
            }
            return text.contains(variant)
        }
    }

    private static func matchVariants(_ term: String) -> [String] {
        let normalized = TranscriptCleanup.normalizeChinesePunctuation(term)
        return normalized == term || normalized.isEmpty ? [term] : [term, normalized]
    }

    private static func wordRegex(for term: String) -> NSRegularExpression? {
        guard term.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) && $0.isASCII }) else {
            return nil
        }
        let escaped = NSRegularExpression.escapedPattern(for: term)
        return try? NSRegularExpression(pattern: "(?i)(?<![A-Za-z0-9])\(escaped)(?![A-Za-z0-9])")
    }
}
