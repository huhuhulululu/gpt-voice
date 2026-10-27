import Foundation
import XCTest
@testable import DictationCore

final class AudioPreparationTests: XCTestCase {
    private let rate = 24_000

    func testTooShortRecordingIsRejectedBeforeUpload() {
        let wav = Self.wav(sine(amplitude: 3000, seconds: 0.2))
        XCTAssertThrowsError(try AudioPreparation.prepareForUpload(wav, fileExtension: "wav")) { error in
            XCTAssertEqual(error.localizedDescription, DictationError.recordingTooShort.localizedDescription)
        }
    }

    func testQuietSpeechIsLiftedWithoutClipping() throws {
        let wav = Self.wav(sine(amplitude: 300, seconds: 1))
        let prepared = try AudioPreparation.prepareForUpload(wav, fileExtension: "wav")
        let before = Self.samples(wav)
        let after = Self.samples(prepared)
        XCTAssertEqual(before.count, after.count)
        let peakBefore = before.map { abs(Int($0)) }.max() ?? 0
        let peakAfter = after.map { abs(Int($0)) }.max() ?? 0
        XCTAssertGreaterThanOrEqual(peakAfter, peakBefore * 9, "About +20 dB for a soft voice")
        XCTAssertLessThanOrEqual(peakAfter, Int(32767 * 0.9))
        XCTAssertEqual(prepared.prefix(44), wav.prefix(44), "Header is untouched")
    }

    func testNormalSpeechIsSentUnchanged() throws {
        let wav = Self.wav(sine(amplitude: 8000, seconds: 1))
        XCTAssertEqual(try AudioPreparation.prepareForUpload(wav, fileExtension: "wav"), wav)
    }

    func testNearSilenceIsNotRaisedIntoHallucinationFodder() throws {
        let wav = Self.wav(sine(amplitude: 20, seconds: 1))
        XCTAssertEqual(try AudioPreparation.prepareForUpload(wav, fileExtension: "wav"), wav)
    }

    func testOtherFormatsAndUnreadableFilesPassThrough() throws {
        let bytes = Data([0, 1, 2, 3])
        XCTAssertEqual(try AudioPreparation.prepareForUpload(bytes, fileExtension: "m4a"), bytes)
        XCTAssertEqual(try AudioPreparation.prepareForUpload(bytes, fileExtension: "wav"), bytes)
    }

    func testParsesChunksBeforeDataAndAnUnsetDataSize() throws {
        let samples = sine(amplitude: 300, seconds: 0.5)
        let wav = Self.wav(samples, padding: true, dataSize: 0xFFFF_FFFF)
        let format = try XCTUnwrap(AudioPreparation.pcmFormat([UInt8](wav)))
        XCTAssertEqual(format.sampleRate, rate)
        XCTAssertEqual(format.channels, 1)
        XCTAssertEqual(format.bitsPerSample, 16)
        XCTAssertEqual(format.dataLength, samples.count * 2)
        XCTAssertEqual(format.duration, 0.5, accuracy: 0.001)
    }

    func testGainIsCappedAndRespectsPeaks() {
        XCTAssertEqual(AudioPreparation.gain(speechRMS: 100, peak: 500), 10, accuracy: 0.0001)
        XCTAssertEqual(AudioPreparation.gain(speechRMS: 100, peak: 30_000), 1)
        XCTAssertEqual(AudioPreparation.gain(speechRMS: 3000, peak: 6000), 1, "Already near -20 dBFS")
        XCTAssertEqual(AudioPreparation.gain(speechRMS: 30, peak: 200), 1, "Below the silence floor")
    }

    // MARK: Fixtures

    private func sine(amplitude: Double, seconds: Double) -> [Int16] {
        (0..<Int(Double(rate) * seconds)).map { index in
            Int16((amplitude * sin(2 * .pi * 220 * Double(index) / Double(rate))).rounded())
        }
    }

    static func wav(_ samples: [Int16], rate: Int = 24_000, padding: Bool = false,
                    dataSize: UInt32? = nil) -> Data {
        var bytes: [UInt8] = []
        func ascii(_ text: String) { bytes += Array(text.utf8) }
        func u16(_ value: UInt16) { bytes += [UInt8(value & 0xFF), UInt8(value >> 8)] }
        func u32(_ value: UInt32) { bytes += (0..<4).map { UInt8((value >> (8 * UInt32($0))) & 0xFF) } }
        let payload = samples.count * 2
        ascii("RIFF"); u32(UInt32(36 + payload)); ascii("WAVE")
        ascii("fmt "); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        if padding { ascii("FLLR"); u32(6); bytes += [0, 0, 0, 0, 0, 0] }
        ascii("data"); u32(dataSize ?? UInt32(payload))
        for sample in samples { u16(UInt16(bitPattern: sample)) }
        return Data(bytes)
    }

    static func samples(_ wav: Data) -> [Int16] {
        let bytes = [UInt8](wav)
        guard let format = AudioPreparation.pcmFormat(bytes) else { return [] }
        return stride(from: format.dataOffset, to: format.dataOffset + format.dataLength, by: 2).map { offset in
            Int16(bitPattern: UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8)
        }
    }
}
