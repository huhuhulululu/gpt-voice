import XCTest
@testable import DictationCore

/// The word list must reach the Groq / OpenAI-compatible upload as the multipart `prompt` field.
final class LexiconPromptRequestTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    func testLexiconPromptIsSentAsTheMultipartPromptField() async throws {
        var lexicon = Lexicon()
        lexicon.addTerm("锄禾日当午")
        lexicon.addTerm("采菊东篱下")
        let prompt = try XCTUnwrap(lexicon.transcriptionPrompt(language: "zh"))
        XCTAssertTrue(prompt.hasPrefix("以下是普通话的句子。可能出现的词："))

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("goice-prompt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("take.wav")
        try Self.toneWAV(seconds: 0.5).write(to: file)

        StubURLProtocol.response = (200, Data(#"{"text":"锄禾日当午"}"#.utf8))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let text = try await TranscriptionService.transcribe(
            file: file, provider: .openAICompatible, language: "zh", prompt: prompt,
            openAI: OpenAICompatibleEndpoint(baseURL: "https://api.groq.com/openai/v1", model: "whisper-large-v3",
                                             language: "zh"),
            apiKey: "gsk-test", session: URLSession(configuration: config))
        XCTAssertEqual(text, "锄禾日当午")

        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.absoluteString,
                       "https://api.groq.com/openai/v1/audio/transcriptions")
        let body = String(decoding: try XCTUnwrap(StubURLProtocol.lastBody), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"prompt\"\r\n\r\n\(prompt)\r\n"), "Prompt field carries the lexicon prompt")
        XCTAssertTrue(body.contains("锄禾日当午、采菊东篱下") || body.contains("采菊东篱下、锄禾日当午"))
        XCTAssertTrue(body.contains("name=\"language\"\r\n\r\nzh\r\n"))
        XCTAssertTrue(body.contains("name=\"response_format\"\r\n\r\nverbose_json\r\n"))
    }

    private static func toneWAV(seconds: Double) -> Data {
        let rate = 16_000
        let samples = (0..<Int(Double(rate) * seconds)).map {
            Int16(8000 * sin(2 * Double.pi * 440 * Double($0) / Double(rate)))
        }
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let payload = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + payload))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(rate)); append(UInt32(rate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(payload))
        samples.forEach { append($0) }
        return data
    }
}
