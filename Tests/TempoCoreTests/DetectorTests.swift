import XCTest
@testable import TempoCore

final class DetectorTests: XCTestCase {
    private func analyze(_ samples: [Float], rate: Double = 48_000, block: Int = 1024,
                         settings: DetectorSettings = .init()) -> (AnalysisSnapshot, Int) {
        var analyzer = ClickAnalyzer(sampleRate: rate, settings: settings)
        var snapshot = analyzer.process([], startingAt: 0)
        var onsets = 0
        for start in stride(from: 0, to: samples.count, by: block) {
            snapshot = analyzer.process(Array(samples[start..<min(samples.count, start + block)]), startingAt: Double(start) / rate)
            onsets += snapshot.detectedOnsets
        }
        return (snapshot, onsets)
    }
    private func clicks(rate: Double = 48_000, bpm: Double = 120, seconds: Double = 6) -> [Float] {
        TestSignal.samples(startFrame: 0, count: Int(rate * seconds), sampleRate: rate, pulsesPerMinute: bpm)
    }
    func testSampleRatesTemposAndAccentedClickPitches() {
        for rate in [44_100.0, 48_000, 96_000, 192_000] {
            for bpm in [40.0, 73, 120, 237, 600] {
                let duration = 60 / bpm * 7
                let (snapshot, count) = analyze(clicks(rate: rate, bpm: bpm, seconds: duration), rate: rate)
                XCTAssertEqual(count, 7, "\(rate) Hz / \(bpm) CPM")
                XCTAssertEqual(snapshot.reading.pulseMilliseconds!, 60_000 / bpm, accuracy: 0.08)
                XCTAssertTrue(snapshot.reading.isStable)
            }
        }
    }
    func testBlockSizeDoesNotAffectTiming() {
        let signal = clicks(seconds: 4)
        let baseline = analyze(signal, block: 128)
        for block in [1, 63, 511, 2048, 8192] {
            let result = analyze(signal, block: block)
            XCTAssertEqual(result.1, baseline.1)
            XCTAssertEqual(result.0.reading.pulseMilliseconds!, baseline.0.reading.pulseMilliseconds!, accuracy: 1e-9)
            XCTAssertEqual(result.0.discontinuities, 0)
        }
    }
    func testLongRingingClickIsOnlyCountedOnce() {
        let rate = 48_000.0
        let signal = (0..<Int(rate * 6)).map { frame -> Float in
            let phase = Double(frame % 24_000) / rate
            return phase < 0.15 ? Float(0.7 * exp(-phase * 20) * sin(2 * .pi * 880 * phase)) : 0
        }
        let result = analyze(signal)
        XCTAssertEqual(result.1, 12)
        XCTAssertEqual(result.0.reading.pulseMilliseconds!, 500, accuracy: 0.1)
    }
    func testNoiseAndDCOffset() {
        var rng: UInt64 = 42
        let signal = clicks().map { sample -> Float in
            rng = rng &* 6364136223846793005 &+ 1
            let noise = (Double(rng >> 32) / Double(UInt32.max) - 0.5) * 0.006
            return sample + Float(noise) + 0.1
        }
        let result = analyze(signal)
        XCTAssertEqual(result.1, 12)
        XCTAssertEqual(result.0.reading.pulseMilliseconds!, 500, accuracy: 0.15)
    }
    func testBelowThresholdAndSilence() {
        for signal in [[Float](repeating: 0, count: 48_000), clicks().map { $0 * 0.005 }] {
            let result = analyze(signal)
            XCTAssertEqual(result.1, 0)
            XCTAssertNil(result.0.reading.pulseMilliseconds)
        }
    }
    func testLowerThresholdFindsQuietClicks() {
        let result = analyze(clicks().map { $0 * 0.02 }, settings: .init(thresholdDB: -50))
        XCTAssertEqual(result.1, 12)
        XCTAssertTrue(result.0.reading.isStable)
    }
    func testClippedClicksStillHaveCorrectTiming() {
        let signal = clicks().map { max(-1, min(1, $0 * 15)) }
        let result = analyze(signal)
        XCTAssertEqual(result.1, 12)
        XCTAssertEqual(result.0.reading.pulseMilliseconds!, 500, accuracy: 0.2)
    }
    func testNonFiniteAudioDoesNotPoisonDetector() {
        var signal = clicks()
        signal[1000] = .nan; signal[2000] = .infinity; signal[3000] = -.infinity
        let result = analyze(signal)
        XCTAssertEqual(result.1, 12)
        XCTAssertTrue(result.0.reading.isStable)
    }
    func testStaleAfterSilentAudio() {
        let result = analyze(clicks(seconds: 3) + [Float](repeating: 0, count: 48_000 * 4))
        XCTAssertTrue(result.0.reading.isStale)
        XCTAssertEqual(result.0.reading.pulseMilliseconds!, 500, accuracy: 0.1)
    }
    func testSampleTimestampJumpClearsOldTempo() {
        var analyzer = ClickAnalyzer(sampleRate: 48_000)
        let before = analyzer.process(clicks(seconds: 3), startingAt: 0)
        XCTAssertTrue(before.reading.isStable)
        let gap = analyzer.process([Float](repeating: 0, count: 1024), startingAt: 8)
        XCTAssertEqual(gap.discontinuities, 1)
        XCTAssertNil(gap.reading.pulseMilliseconds)
        let backwards = analyzer.process([0, 0], startingAt: 0)
        XCTAssertEqual(backwards.discontinuities, 2)
    }
    func testGuardSuppressesShortEchoes() {
        var signal = clicks(seconds: 4)
        for beat in 0..<8 {
            let echo = beat * 24000 + 2400
            signal[echo] = 0.7
        }
        let result = analyze(signal)
        XCTAssertEqual(result.1, 8)
        XCTAssertEqual(result.0.reading.pulseMilliseconds!, 500, accuracy: 0.1)
    }
    func testEchoTailCannotTriggerWhenGuardExpires() {
        var detector = ClickDetector(sampleRate: 48_000)
        var onsets: [Double] = []
        for frame in 0..<24000 {
            let time = Double(frame) / 48_000
            let sample: Float = frame == 0 ? 0.8 : (time >= 0.07 && time < 0.12 ? Float(0.6 * sin(2 * .pi * 880 * time)) : 0)
            if detector.process(sample: sample, at: time) { onsets.append(time) }
        }
        XCTAssertEqual(onsets, [0])
    }
    func testSettingsAreSanitized() {
        XCTAssertEqual(DetectorSettings(thresholdDB: .nan).thresholdDB, -30)
        XCTAssertEqual(DetectorSettings(thresholdDB: 10).thresholdDB, -3)
        XCTAssertEqual(DetectorSettings(retriggerMilliseconds: 0).retriggerMilliseconds, 40)
    }
    func testThresholdCanMeasureOnlyBarAccents() {
        // Stable does not prove beat interpretation. This limitation is explained in the UI.
        let result = analyze(clicks(seconds: 12), settings: .init(thresholdDB: -6))
        XCTAssertEqual(result.1, 6)
        XCTAssertEqual(result.0.reading.pulseMilliseconds!, 2000, accuracy: 0.1)
    }
}
