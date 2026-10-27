import Foundation

/// One `verbose_json` segment. Providers omit fields freely, so every score is optional.
public struct TranscriptSegment: Equatable, Sendable {
    public var text: String
    public var noSpeechProbability: Double?
    public var averageLogProbability: Double?
    public var compressionRatio: Double?

    public init(text: String, noSpeechProbability: Double? = nil, averageLogProbability: Double? = nil,
                compressionRatio: Double? = nil) {
        self.text = text
        self.noSpeechProbability = noSpeechProbability
        self.averageLogProbability = averageLogProbability
        self.compressionRatio = compressionRatio
    }

    init?(json: [String: Any]) {
        guard let text = json["text"] as? String else { return nil }
        func number(_ key: String) -> Double? { (json[key] as? NSNumber)?.doubleValue }
        self.init(text: text, noSpeechProbability: number("no_speech_prob"),
                  averageLogProbability: number("avg_logprob"), compressionRatio: number("compression_ratio"))
    }
}

/// Drops `verbose_json` segments that Whisper itself would treat as silence or a failed decode.
/// The thresholds are Whisper's own defaults, so ordinary speech is never cut.
public enum HallucinationGate {
    /// Above this, a low-confidence segment is silence that Whisper filled in ("谢谢观看", "Thank you.").
    public static let noSpeechThreshold = 0.6
    public static let logProbabilityThreshold = -1.0
    /// Near-certain silence regardless of the decoder's confidence.
    public static let certainNoSpeech = 0.95
    /// Above this, gzip finds the text so repetitive that decoding has looped.
    public static let compressionRatioThreshold = 2.4

    public static func isLikelyHallucination(_ segment: TranscriptSegment) -> Bool {
        if let ratio = segment.compressionRatio, ratio > compressionRatioThreshold { return true }
        guard let noSpeech = segment.noSpeechProbability else { return false }
        if noSpeech >= certainNoSpeech { return true }
        guard noSpeech > noSpeechThreshold, let logProbability = segment.averageLogProbability else { return false }
        return logProbability <= logProbabilityThreshold
    }

    /// The provider's `text` when nothing is dropped; otherwise the kept segments rejoined.
    public static func filter(text: String, segments: [TranscriptSegment]) -> String {
        guard !segments.isEmpty else { return text }
        let kept = segments.filter { !isLikelyHallucination($0) }
        if kept.count == segments.count { return text }
        return kept.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce("") { joined, next in
                guard let last = joined.unicodeScalars.last, let first = next.unicodeScalars.first else {
                    return joined + next
                }
                return joined + (last.isASCII && first.isASCII ? " " : "") + next
            }
    }
}
