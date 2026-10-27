import XCTest
@testable import DictationCore

final class HallucinationGateTests: XCTestCase {
    func testKeepsConfidentSpeechAndProviderText() {
        let segments = [
            TranscriptSegment(text: " 今天开会", noSpeechProbability: 0.02, averageLogProbability: -0.2, compressionRatio: 1.1),
            TranscriptSegment(text: "讨论预算。", noSpeechProbability: 0.7, averageLogProbability: -0.3, compressionRatio: 1.2),
        ]
        XCTAssertEqual(HallucinationGate.filter(text: "今天开会讨论预算。", segments: segments), "今天开会讨论预算。")
    }

    func testDropsSilenceFillersAndLoops() {
        let segments = [
            TranscriptSegment(text: " Ship it today.", noSpeechProbability: 0.01, averageLogProbability: -0.25,
                              compressionRatio: 1.3),
            TranscriptSegment(text: " Thank you for watching.", noSpeechProbability: 0.82,
                              averageLogProbability: -1.3, compressionRatio: 1.0),
            TranscriptSegment(text: " Then review.", noSpeechProbability: 0.05, averageLogProbability: -0.3,
                              compressionRatio: 1.2),
            TranscriptSegment(text: " la la la la la la la la", noSpeechProbability: 0.1,
                              averageLogProbability: -0.2, compressionRatio: 3.1),
        ]
        XCTAssertEqual(HallucinationGate.filter(text: "unused", segments: segments), "Ship it today. Then review.")
    }

    func testAllSilenceBecomesEmptyAndMissingScoresAreKept() {
        XCTAssertEqual(HallucinationGate.filter(text: "谢谢观看", segments: [
            TranscriptSegment(text: "谢谢观看", noSpeechProbability: 0.97),
        ]), "")
        XCTAssertFalse(HallucinationGate.isLikelyHallucination(TranscriptSegment(text: "hi", noSpeechProbability: 0.8)))
        XCTAssertFalse(HallucinationGate.isLikelyHallucination(TranscriptSegment(text: "hi")))
        XCTAssertEqual(HallucinationGate.filter(text: "plain", segments: []), "plain")
    }

    func testJoinsChineseWithoutSpaces() {
        let segments = [
            TranscriptSegment(text: "第一句。", noSpeechProbability: 0.0, averageLogProbability: -0.1),
            TranscriptSegment(text: "字幕由Amara.org社区提供", noSpeechProbability: 0.9, averageLogProbability: -1.4),
            TranscriptSegment(text: " 第二句。", noSpeechProbability: 0.0, averageLogProbability: -0.1),
        ]
        XCTAssertEqual(HallucinationGate.filter(text: "x", segments: segments), "第一句。第二句。")
    }
}
