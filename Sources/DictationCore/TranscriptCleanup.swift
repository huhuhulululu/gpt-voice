import Foundation

/// Deterministic post-STT cleanup. No network, no Apple Intelligence.
/// Filter-word and trailing-phrase ideas follow groq-menubar-dictate / murmur lists.
public enum TranscriptCleanup {
    public static let defaultFilterWords = [
        "um", "umm", "uh", "uhh", "uhm", "er", "erm", "hmm", "mm", "mmm",
        "嗯", "呃", "额", "唔"
    ]

    /// High-confidence Whisper silence / caption leaks. Removed as the whole transcript or a trailing sign-off.
    public static let defaultEndPrunePhrases = [
        "thanks for watching",
        "thank you for watching",
        "thanks for listening",
        "thank you for listening",
        "like and subscribe",
        "please subscribe",
        "subtitles by the amara.org community",
        "subtitles by",
        "谢谢观看",
        "感谢观看",
        "謝謝觀看",
        "谢谢收看",
        "感谢收看",
        "谢谢大家收看",
        "请订阅",
        "字幕由amara.org社区提供",
        "请不吝点赞 订阅 转发 打赏支持明镜与点点栏目",
        "明镜需要您的支持 欢迎订阅明镜",
        "以下是普通话的句子"
    ]

    /// Common words Whisper also invents on silence. Removed only when they are the whole transcript,
    /// so a dictated "…by Friday. Thank you." keeps its sign-off.
    public static let defaultWholeTranscriptPhrases = ["thank you", "thanks", "thank you very much", "you"]

    public static func apply(
        _ text: String,
        filterWords: [String] = defaultFilterWords,
        endPrunePhrases: [String] = defaultEndPrunePhrases,
        wholeTranscriptPhrases: [String] = defaultWholeTranscriptPhrases
    ) -> String {
        var result = stripBlankAudioMarkers(text)
        result = stripFilterWords(result, words: filterWords)
        result = pruneTrailingPhrases(result, phrases: endPrunePhrases)
        result = normalizeWhitespaceAndPunctuation(result)
        result = normalizeChinesePunctuation(result)
        if isWholeTranscript(result, in: wholeTranscriptPhrases) { return "" }
        return result
    }

    static func stripBlankAudioMarkers(_ text: String) -> String {
        let markers = ["[BLANK_AUDIO]", "[blank_audio]", "(blank)", "(BLANK)"]
        var result = text
        for marker in markers {
            result = result.replacingOccurrences(of: marker, with: " ", options: .caseInsensitive)
        }
        return result
    }

    /// Latin words go as whole tokens (`um`, `um,`). CJK fillers go only when they stand alone between
    /// punctuation, spaces, or the ends, so 金额, 额外, and 名额 keep their 额.
    static func stripFilterWords(_ text: String, words: [String]) -> String {
        var result = text
        for raw in words {
            let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { continue }
            if word.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) && $0.isASCII }) {
                result = stripLatinFilter(result, word: word)
            } else {
                result = stripStandaloneFilter(result, word: word)
            }
        }
        return result
    }

    private static func stripLatinFilter(_ text: String, word: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        return replace("(?i)(?<![A-Za-z0-9])\(escaped)(?![A-Za-z0-9])[,.]?", in: text, with: " ")
    }

    private static func stripStandaloneFilter(_ text: String, word: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        return replace("(^|[\\s\\p{P}])(?:\(escaped))+(?=$|[\\s\\p{P}])", in: text, with: "$1")
    }

    /// Removes a known hallucination when it is the whole transcript or a trailing sign-off.
    /// Latin phrases need a space or punctuation before them; CJK phrases can follow text directly.
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
                let boundary = containsCJK(phrase) ? "" : "(?:\\s+|(?<=[\\p{P}]))"
                if let range = result.range(of: "(?i)\(boundary)\(escaped)[\\s[:punct:]]*$",
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

    /// Collapses spaces and repairs punctuation left by removals. Never inserts a space after punctuation,
    /// so 3.14, v1.2, and example.com stay intact.
    static func normalizeWhitespaceAndPunctuation(_ text: String) -> String {
        let cjk = "[\\p{Han}\\p{Hiragana}\\p{Katakana}\\u3000-\\u303F\\uFF00-\\uFFEF]"
        var result = replace("\\s+", in: text, with: " ")
        result = replace("\\s+([,.;:!?])", in: result, with: "$1")
        result = replace("(?<=\(cjk))\\s+(?=\(cjk))", in: result, with: "")
        result = replace("([，、,])\\s*[，、,]+", in: result, with: "$1")
        result = replace("[，、,]\\s*([。！？.!?])", in: result, with: "$1")
        result = replace("^[\\s，、,；;]+", in: result, with: "")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Chinese text only (Han without kana): fullwidth letters and digits become ASCII, ASCII
    /// punctuation after a Han character becomes Chinese punctuation, spaces around Chinese
    /// punctuation go, and doubled 。 or ， collapse. `3.14`, `v1.2`, `12:30` and English stay as they are.
    public static func normalizeChinesePunctuation(_ text: String) -> String {
        guard containsHan(text), !containsKana(text) else { return text }
        var result = String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            switch scalar.value {
            case 0xFF10...0xFF19, 0xFF21...0xFF3A, 0xFF41...0xFF5A:
                return Unicode.Scalar(scalar.value - 0xFEE0) ?? scalar
            default:
                return scalar
            }
        }))
        let han = "\\p{Han}"
        result = replace("(?<=\(han))\\s*(?:\\.{3,}|…+)", in: result, with: "……")
        result = replace("(?<=\(han))\\s*,\\s*", in: result, with: "，")
        result = replace("(?<=\(han))\\s*\\?\\s*", in: result, with: "？")
        result = replace("(?<=\(han))\\s*!\\s*", in: result, with: "！")
        result = replace("(?<=\(han))\\s*;\\s*", in: result, with: "；")
        result = replace("(?<=\(han))\\s*:\\s*(?=\\D|$)", in: result, with: "：")
        result = replace("(?<=\(han))\\s*\\.(?=\\s*$|\\s*\\p{Han})\\s*", in: result, with: "。")
        result = replace("\\s+(?=[，。！？；：、）」』】》])", in: result, with: "")
        result = replace("(?<=[，。！？；：、（「『【《])\\s+", in: result, with: "")
        result = replace("。{2,}", in: result, with: "。")
        result = replace("，{2,}", in: result, with: "，")
        result = replace("[，、]+(?=[。！？])", in: result, with: "")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
    }

    static func containsKana(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) }
    }

    static func isWholeTranscript(_ text: String, in phrases: [String]) -> Bool {
        let core = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .lowercased()
        return !core.isEmpty && phrases.contains { $0.lowercased() == core }
    }

    static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) || (0x3400...0x9FFF).contains($0.value) }
    }

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
