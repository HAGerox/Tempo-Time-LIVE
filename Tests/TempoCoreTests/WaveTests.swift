import XCTest
@testable import TempoCore

final class WaveTests: XCTestCase {
    private func little(_ value: Int, bytes: Int) -> [UInt8] { (0..<bytes).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) } }
    private func wave(bits: Int = 16, format: Int = 1, channels: Int = 2,
                      samples: [UInt8] = [0, 128, 255, 127], extensible: Bool = false, junk: Bool = false) -> Data {
        var fmt = little(extensible ? 0xfffe : format, bytes: 2) + little(channels, bytes: 2)
        fmt += little(48000, bytes: 4) + little(48000 * channels * bits / 8, bytes: 4)
        fmt += little(channels * bits / 8, bytes: 2) + little(bits, bytes: 2)
        if extensible {
            fmt += little(22, bytes: 2) + little(bits, bytes: 2) + little(0, bytes: 4)
            fmt += little(format, bytes: 4) + [0, 0, 16, 0, 128, 0, 0, 170, 0, 56, 155, 113]
        }
        var body = Array("WAVE".utf8)
        if junk { body += Array("JUNK".utf8) + little(3, bytes: 4) + [1, 2, 3, 0] }
        body += Array("fmt ".utf8) + little(fmt.count, bytes: 4) + fmt
        body += Array("data".utf8) + little(samples.count, bytes: 4) + samples
        if samples.count % 2 == 1 { body += [0] }
        return Data(Array("RIFF".utf8) + little(body.count, bytes: 4) + body)
    }
    func testPCM16ChannelSelectionAndOddChunkPadding() throws {
        let audio = try WaveFile(data: wave(junk: true))
        XCTAssertEqual(audio.channels, 2); XCTAssertEqual(audio.frameCount, 1)
        XCTAssertEqual(try audio.samples(channel: 0, frames: 0..<1), [-1])
        XCTAssertEqual(try audio.samples(channel: 1, frames: 0..<1)[0], 32767 / 32768, accuracy: 0.000001)
    }
    func testPCM24SignExtension() throws {
        let audio = try WaveFile(data: wave(bits: 24, samples: [0, 0, 128, 255, 255, 127]))
        XCTAssertEqual(try audio.samples(channel: 0, frames: 0..<1), [-1])
        XCTAssertEqual(try audio.samples(channel: 1, frames: 0..<1)[0], 1, accuracy: 0.000001)
    }
    func testPCM32() throws {
        let audio = try WaveFile(data: wave(bits: 32, samples: [0, 0, 0, 128, 255, 255, 255, 127]))
        XCTAssertEqual(try audio.samples(channel: 0, frames: 0..<1), [-1])
    }
    func testFloat32AndExtensibleFormats() throws {
        for extensible in [false, true] {
            let bytes = little(Int(Float(-0.25).bitPattern), bytes: 4) + little(Int(Float.nan.bitPattern), bytes: 4)
            let audio = try WaveFile(data: wave(bits: 32, format: 3, samples: bytes, extensible: extensible))
            XCTAssertEqual(try audio.samples(channel: 0, frames: 0..<1), [-0.25])
            XCTAssertEqual(try audio.samples(channel: 1, frames: 0..<1), [0])
        }
        let pcm = try WaveFile(data: wave(extensible: true))
        XCTAssertEqual(try pcm.samples(channel: 0, frames: 0..<1), [-1])
    }
    func testEmptyDataAndInvalidChannels() throws {
        let audio = try WaveFile(data: wave(samples: []))
        XCTAssertEqual(audio.frameCount, 0)
        XCTAssertEqual(try audio.samples(channel: 0, frames: 0..<0), [])
        XCTAssertThrowsError(try audio.samples(channel: 2, frames: 0..<0))
        XCTAssertThrowsError(try audio.samples(channel: -1, frames: 0..<0))
        XCTAssertThrowsError(try audio.samples(channel: 0, frames: 0..<1))
    }
    func testTruncationAndMalformedChunks() {
        let valid = wave()
        for end in 0..<valid.count { XCTAssertThrowsError(try WaveFile(data: valid.prefix(end)), "Prefix \(end)") }
        var broken = valid
        broken[16] = 255; broken[17] = 255; broken[18] = 255; broken[19] = 127
        XCTAssertThrowsError(try WaveFile(data: broken))
        XCTAssertThrowsError(try WaveFile(data: wave(bits: 8)))
        XCTAssertThrowsError(try WaveFile(data: wave(format: 6)))
        XCTAssertThrowsError(try WaveFile(data: wave(channels: 0)))
        XCTAssertThrowsError(try WaveFile(data: wave(samples: [0])))
    }
    func testRandomMalformedDataDoesNotCrash() {
        var state: UInt64 = 83
        for size in 0..<512 {
            let bytes = (0..<size).map { _ -> UInt8 in
                state = state &* 6364136223846793005 &+ 1
                return UInt8(truncatingIfNeeded: state >> 32)
            }
            XCTAssertThrowsError(try WaveFile(data: Data(bytes)))
        }
    }
}
