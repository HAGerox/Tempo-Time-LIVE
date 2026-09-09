import Foundation

public enum WaveError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

/// Bounded RIFF/WAVE reader for the test CLI. PCM 16/24/32 and IEEE float32,
/// including WAVE_FORMAT_EXTENSIBLE; no implicit channel mixdown.
public struct WaveFile {
    public let sampleRate: Double
    public let channels: Int
    public let frameCount: Int
    private let data: Data
    private let audioRange: Range<Int>
    private let bits: Int
    private let format: Int
    private let blockAlign: Int

    public init(data: Data) throws {
        func invalid(_ text: String) -> WaveError { .invalid(text) }
        guard data.count >= 12, String(data: data[0..<4], encoding: .ascii) == "RIFF",
              String(data: data[8..<12], encoding: .ascii) == "WAVE" else { throw invalid("Expected a RIFF/WAVE file.") }
        func u16(_ offset: Int) -> Int { Int(data[offset]) | Int(data[offset + 1]) << 8 }
        func u32(_ offset: Int) -> Int { u16(offset) | u16(offset + 2) << 16 }
        let riffEnd = u32(4) + 8
        guard riffEnd <= data.count, riffEnd >= 12 else { throw invalid("Truncated RIFF container.") }
        var cursor = 12
        var fmt: Range<Int>?
        var audio: Range<Int>?
        while cursor + 8 <= riffEnd {
            let length = u32(cursor + 4)
            let start = cursor + 8
            guard length <= riffEnd - start else { throw invalid("Truncated WAVE chunk.") }
            let name = String(data: data[cursor..<cursor + 4], encoding: .ascii)
            if name == "fmt " { fmt = start..<start + length }
            if name == "data", audio == nil { audio = start..<start + length }
            cursor = start + length + length % 2
        }
        guard let fmt = fmt, fmt.count >= 16, let audio = audio else { throw invalid("Missing WAVE format or audio data.") }
        let f = fmt.lowerBound
        var encoding = u16(f)
        let channels = u16(f + 2), rate = u32(f + 4), align = u16(f + 12), bits = u16(f + 14)
        if encoding == 0xfffe {
            guard fmt.count >= 40, u16(f + 16) >= 22,
                  Array(data[f + 26..<f + 40]) == [0, 0, 0, 0, 16, 0, 128, 0, 0, 170, 0, 56, 155, 113] else {
                throw invalid("Unsupported extensible WAVE format.")
            }
            let validBits = u16(f + 18)
            guard validBits == 0 || validBits == bits else { throw invalid("Packed valid-bit WAVE formats are unsupported.") }
            encoding = u16(f + 24)
        }
        guard channels > 0, channels <= 1024, (8_000...384_000).contains(rate),
              (encoding == 1 && [16, 24, 32].contains(bits)) || (encoding == 3 && bits == 32),
              align == channels * (bits / 8), audio.count % align == 0 else { throw invalid("Unsupported or inconsistent WAVE format. Use PCM 16/24/32-bit or float32.") }
        self.data = data; self.audioRange = audio; self.bits = bits; self.format = encoding
        self.sampleRate = Double(rate); self.channels = channels; self.blockAlign = align
        self.frameCount = audio.count / align
    }

    public func samples(channel: Int, frames: Range<Int>) throws -> [Float] {
        guard (0..<channels).contains(channel), frames.lowerBound >= 0, frames.upperBound <= frameCount else {
            throw WaveError.invalid("Channel or frame range is outside the WAVE file.")
        }
        return frames.map { frame in
            let offset = audioRange.lowerBound + frame * blockAlign + channel * (bits / 8)
            var raw: UInt32 = 0
            for byte in 0..<bits / 8 { raw |= UInt32(data[offset + byte]) << (byte * 8) }
            if format == 3 { let value = Float(bitPattern: raw); return value.isFinite ? value : 0 }
            if bits == 16 { return Float(Int16(bitPattern: UInt16(raw))) / 32768 }
            if bits == 24 { return Float(Int32(bitPattern: raw << 8) >> 8) / 8388608 }
            return Float(Int32(bitPattern: raw)) / 2147483648
        }
    }
}
