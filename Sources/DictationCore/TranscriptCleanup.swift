import Foundation

/// Deterministic post-STT cleanup. No network, no Apple Intelligence.
/// Filter-word and trailing-phrase ideas follow groq-menubar-dictate / murmur lists.
public enum TranscriptCleanup {
    public static let defaultFilterWords = [
        "um", "umm", "uh", "uhh", "uhm", "er", "erm", "hmm", "mm", "mmm",
        "嗯", "呃", "额", "唔"
    ]

    /// High-confidence Whisper silence/YouTube leaks. Applied only at the tail or as the whole transcript.
    public static let defaultEndPrunePhrases = [
        "thanks for watching",
        "thank you for watching",
        "thanks for listening",
        "thank you for listening",
        "like and subscribe",
        "please subscribe",
        "subtitles by the amara.org community",
        "subtitles by",
        "thank you",
        "thanks",
        "谢谢观看",
        "感谢观看",
        "謝謝觀看",
        "请订阅"
    ]

    public static func apply(
        _ text: String,
        filterWords: [String] = defaultFilterWords,
        endPrunePhrases: [String] = defaultEndPrunePhrases
    ) -> String {
        var result = stripBlankAudioMarkers(text)
        result = stripFilterWords(result, words: filterWords)
        result = pruneTrailingPhrases(result, phrases: endPrunePhrases)
        return normalizeWhitespaceAndPunctuation(result)
    }

    static func stripBlankAudioMarkers(_ text: String) -> String {
        let markers = ["[BLANK_AUDIO]", "[blank_audio]", "(blank)", "(BLANK)"]
        var result = text
        for marker in markers {
            result = result.replacingOccurrences(of: marker, with: " ", options: .caseInsensitive)
        }
        return result
    }

    /// Case-insensitive chunk removal: `word`, `word,`, `word.` as whole tokens.
    static func stripFilterWords(_ text: String, words: [String]) -> String {
        var result = text
        for raw in words {
            let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { continue }
            if word.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) && $0.isASCII }) {
                result = stripLatinFilter(result, word: word)
            } else {
                result = result.replacingOccurrences(of: word, with: " ")
            }
        }
        return result
    }

    private static func stripLatinFilter(_ text: String, word: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        let pattern = "(?i)(?<![A-Za-z0-9])\(escaped)(?![A-Za-z0-9])[,.]?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
    }

    /// Removes a known hallucination only when it is the whole transcript or a trailing sign-off.
    static func pruneTrailingPhrases(_ text: String, phrases: [String]) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let ordered = phrases.sorted { $0.count > $1.count }
        var changed = true
        while changed, !result.isEmpty {
            changed = false
            for phrase in ordered {
                let escaped = NSRegularExpression.escapedPattern(for: phrase)
                if result.range(of: "(?i)^\\s*\(escaped)[\\s[:punct:]]*$", options: .regularExpression) != nil {
                    return ""
                }
                if let range = result.range(of: "(?i)\\s+\(escaped)[\\s[:punct:]]*$",
                                            options: .regularExpression) {
                    result = String(result[..<range.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    changed = true
                    break
                }
            }
        }
        return result
    }

    static func normalizeWhitespaceAndPunctuation(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\s+([,.;:!?])", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "([,.;:!?])([A-Za-z0-9])", with: "$1 $2",
                                             options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
