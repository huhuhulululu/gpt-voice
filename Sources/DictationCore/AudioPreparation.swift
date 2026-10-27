import Foundation

/// Readies a recording for speech-to-text. Only parsed 16-bit PCM WAV is changed; anything else
/// passes through untouched.
public enum AudioPreparation {
    /// Shorter takes are almost always an accidental hold, and Whisper fills them with a hallucination.
    public static let minimumDuration: TimeInterval = 0.3

    public struct PCMFormat: Equatable, Sendable {
        public var sampleRate: Int
        public var channels: Int
        public var bitsPerSample: Int
        public var dataOffset: Int
        public var dataLength: Int

        public var duration: TimeInterval {
            let bytesPerSecond = sampleRate * channels * max(1, bitsPerSample / 8)
            return bytesPerSecond > 0 ? Double(dataLength) / Double(bytesPerSecond) : 0
        }
    }

    /// Throws `recordingTooShort` for a WAV under `minimumDuration`. Lifts quiet 16-bit speech.
    public static func prepareForUpload(_ audio: Data, fileExtension: String) throws -> Data {
        guard fileExtension.lowercased() == "wav" else { return audio }
        var bytes = [UInt8](audio)
        guard let format = pcmFormat(bytes) else { return audio }
        if format.duration < minimumDuration { throw DictationError.recordingTooShort }
        guard format.bitsPerSample == 16, normalizePCM16(&bytes, format: format) else { return audio }
        return Data(bytes)
    }

    // MARK: WAV

    public static func pcmFormat(_ bytes: [UInt8]) -> PCMFormat? {
        guard bytes.count >= 12, fourCC(bytes, 0) == "RIFF", fourCC(bytes, 8) == "WAVE" else { return nil }
        var offset = 12
        var format: (tag: Int, channels: Int, rate: Int, bits: Int)?
        while offset + 8 <= bytes.count {
            let id = fourCC(bytes, offset)
            let size = Int(uint32(bytes, offset + 4))
            let body = offset + 8
            if id == "fmt ", size >= 16, body + 16 <= bytes.count {
                var tag = Int(uint16(bytes, body))
                if tag == 0xFFFE, size >= 40, body + 26 <= bytes.count {
                    tag = Int(uint16(bytes, body + 24))
                }
                format = (tag, Int(uint16(bytes, body + 2)), Int(uint32(bytes, body + 4)), Int(uint16(bytes, body + 14)))
            } else if id == "data" {
                guard let format, format.tag == 1, format.channels > 0, format.rate > 0, format.bits > 0 else {
                    return nil
                }
                // Recorders can leave the size unset or larger than the file. Trust the bytes that exist.
                let length = min(size, bytes.count - body)
                return PCMFormat(sampleRate: format.rate, channels: format.channels, bitsPerSample: format.bits,
                                 dataOffset: body, dataLength: max(0, length))
            }
            offset = body + size + (size & 1)
        }
        return nil
    }

    // MARK: Level

    /// Gain that brings quiet speech toward -20 dBFS. Leaves normal levels alone (under +3 dB), never
    /// raises a near-silent take (below -55 dBFS speech level), caps at +20 dB, and keeps peaks under -1 dBFS.
    public static func gain(speechRMS: Double, peak: Int) -> Double {
        let fullScale = 32767.0
        guard peak > 0, speechRMS >= fullScale * 0.00178 else { return 1 }
        var gain = (fullScale * 0.1) / speechRMS
        gain = min(gain, 10)
        gain = min(gain, fullScale * 0.89 / Double(peak))
        return gain >= 1.4 ? gain : 1
    }

    /// Speech level: the 90th-percentile 20 ms frame RMS, so pauses do not pull it down.
    static func normalizePCM16(_ bytes: inout [UInt8], format: PCMFormat) -> Bool {
        let start = format.dataOffset
        let sampleCount = format.dataLength / 2
        guard sampleCount > 0 else { return false }
        let frameSize = max(1, format.sampleRate * format.channels / 50)
        var peak = 0
        var frames: [Double] = []
        frames.reserveCapacity(sampleCount / frameSize + 1)
        var sum = 0.0
        var count = 0
        for index in 0..<sampleCount {
            let sample = Int(int16(bytes, start + index * 2))
            peak = max(peak, abs(sample))
            sum += Double(sample * sample)
            count += 1
            if count == frameSize {
                frames.append((sum / Double(count)).squareRoot())
                sum = 0
                count = 0
            }
        }
        if count > frameSize / 2 { frames.append((sum / Double(count)).squareRoot()) }
        guard !frames.isEmpty else { return false }
        frames.sort()
        let speechRMS = frames[min(frames.count - 1, Int(Double(frames.count) * 0.9))]
        let factor = gain(speechRMS: speechRMS, peak: peak)
        guard factor > 1 else { return false }
        for index in 0..<sampleCount {
            let position = start + index * 2
            let scaled = (Double(int16(bytes, position)) * factor).rounded()
            let clamped = Int16(max(-32768, min(32767, scaled)))
            let bits = UInt16(bitPattern: clamped)
            bytes[position] = UInt8(bits & 0xFF)
            bytes[position + 1] = UInt8(bits >> 8)
        }
        return true
    }

    // MARK: Bytes

    private static func fourCC(_ bytes: [UInt8], _ offset: Int) -> String {
        String(decoding: bytes[offset..<offset + 4], as: UTF8.self)
    }

    private static func uint16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func uint32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }

    private static func int16(_ bytes: [UInt8], _ offset: Int) -> Int16 {
        Int16(bitPattern: uint16(bytes, offset))
    }
}
