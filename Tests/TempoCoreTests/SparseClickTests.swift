import XCTest
@testable import TempoCore

final class SparseClickTests: XCTestCase {
    private var empty: AnalysisSnapshot {
        ClickAnalyzer(sampleRate: 48000).emptySnapshot
    }

    func testIsolatedClicksAcquireAndSilenceClears() {
        for rate in [44100.0, 48000, 96000] {
            for bpm in [60.0, 120, 240] {
                var analyzer = SparseClickAnalyzer(sampleRate: rate)
                var last = empty
                let frames = Int(rate * 6)
                for start in stride(from: 0, to: frames, by: 1584) {
                    let samples = TestSignal.samples(startFrame: start, count: min(1584, frames - start), sampleRate: rate, pulsesPerMinute: bpm)
                    last = analyzer.process(samples, startingAt: Double(start) / rate, music: empty)
                }
                XCTAssertEqual(last.reading.pulsesPerMinute ?? 0, bpm, accuracy: 0.1)
                for start in stride(from: frames, to: frames + Int(rate * 4), by: 1584) {
                    last = analyzer.process([Float](repeating: 0, count: 1584), startingAt: Double(start) / rate, music: empty)
                }
                XCTAssertNil(last.reading.pulseMilliseconds)
            }
        }
    }

    func testMusicReadingAlwaysWinsEvenWithRegularClicks() {
        var analyzer = SparseClickAnalyzer(sampleRate: 48000)
        var tracker = TempoTracker()
        for beat in 0..<8 { tracker.addOnset(at: Double(beat) * 0.4) }
        let music = AnalysisSnapshot(reading: tracker.reading(at: 3), peakDB: -6, clipped: false,
                                     detectedOnsets: 1, discontinuities: 0, lastBeatTime: 2.8)
        for start in stride(from: 0, to: 48000 * 6, by: 1584) {
            let result = analyzer.process(TestSignal.samples(startFrame: start, count: 1584),
                                          startingAt: Double(start) / 48000, music: music)
            XCTAssertEqual(result.reading, music.reading)
            XCTAssertEqual(result.lastBeatTime, music.lastBeatTime)
            XCTAssertEqual(result.detectedOnsets, music.detectedOnsets)
        }
    }

    func testSustainedAudioWithRegularTransientsCannotUseFallback() {
        var analyzer = SparseClickAnalyzer(sampleRate: 48000)
        for start in stride(from: 0, to: 48000 * 6, by: 1584) {
            let samples = TestSignal.samples(startFrame: start, count: 1584).enumerated().map {
                $0.element + Float(0.02 * sin(Double(start + $0.offset) * 2 * .pi * 220 / 48000))
            }
            let result = analyzer.process(samples, startingAt: Double(start) / 48000, music: empty)
            XCTAssertNil(result.reading.pulseMilliseconds)
        }
    }

    func testMeterUsesUnmodifiedSamplePeakAndFullScale() {
        for amplitude: Float in [0.5, 0.8, 0.999, 1, 1.2] {
            var analyzer = ClickAnalyzer(sampleRate: 48000)
            let result = analyzer.process([amplitude, -amplitude], startingAt: 0)
            XCTAssertEqual(result.peakDB, 20 * log10(Double(amplitude)), accuracy: 0.00001)
            XCTAssertEqual(result.clipped, amplitude >= 1)
        }
    }
}

private extension ClickAnalyzer {
    var emptySnapshot: AnalysisSnapshot {
        var copy = self
        return copy.process([], startingAt: 0)
    }
}
