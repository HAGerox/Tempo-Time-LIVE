import XCTest
import TempoCore
@testable import TempoInput

final class ClickTrackAnalyzerTests: XCTestCase {
    func testClickModeUsesPulsesWithoutMusicAndSpeechClearsLock() throws {
        let context = ClickContext()
        let analyzer = try ClickTrackAnalyzer(rate: 48000, classifier: context)
        defer { analyzer.stop() }
        var last: AnalysisSnapshot?
        for start in stride(from: 0, to: 48000 * 6, by: 1584) {
            last = try analyzer.process(TestSignal.samples(startFrame: start, count: 1584), startingAt: Double(start) / 48000)
        }
        XCTAssertEqual(try XCTUnwrap(last?.reading.pulsesPerMinute), 120, accuracy: 0.1)
        context.permission = []
        let denied = try analyzer.process(TestSignal.samples(startFrame: 288288, count: 1584), startingAt: 288288.0 / 48000)
        XCTAssertNil(denied.reading.pulseMilliseconds)
        XCTAssertNil(denied.lastBeatTime)
        XCTAssertGreaterThan(denied.peakDB, -120, "Suppression must keep the input meter alive")
        context.permission = [.speechClear]
        let returning = try analyzer.process(TestSignal.samples(startFrame: 289872, count: 1584), startingAt: 289872.0 / 48000)
        XCTAssertNil(returning.reading.pulseMilliseconds, "A prior lock cannot return after the veto closes")
    }

    func testSustainedClickChangesConfirmWithinTenSeconds() throws {
        for target in [90.0, 60.0, 240.0] {
            let analyzer = try ClickTrackAnalyzer(rate: 48000, classifier: ClickContext())
            defer { analyzer.stop() }
            var changedAt: Double?
            var previous: Double?
            for start in stride(from: 0, to: 48000 * 20, by: 2400) {
                let time = Double(start) / 48000
                let changed = time >= 8
                let samples = TestSignal.samples(startFrame: changed ? start - 384000 : start,
                    count: 2400, pulsesPerMinute: changed ? target : 120)
                let result = try analyzer.process(samples, startingAt: time)
                if let bpm = result.reading.pulsesPerMinute {
                    XCTAssertTrue(abs(bpm - 120) < 0.1 || abs(bpm - target) < 0.1,
                                  "A transition must not invent intermediate tempos")
                    if changed && abs(bpm - target) < 0.1 && changedAt == nil { changedAt = time }
                    previous = bpm
                }
            }
            let elapsed = try XCTUnwrap(changedAt) - 8
            print("CLICK CHANGE 120 -> \(target): \(elapsed) seconds")
            XCTAssertGreaterThanOrEqual(elapsed, target == 90 ? 3 : 5)
            XCTAssertLessThanOrEqual(elapsed, 10)
            XCTAssertEqual(try XCTUnwrap(previous), target, accuracy: 0.1)
        }
    }

    func testDiscontinuityResetsContextAndNativeTempo() throws {
        let context = ClickContext()
        let analyzer = try ClickTrackAnalyzer(rate: 48000, classifier: context)
        for start in stride(from: 0, to: 48000 * 6, by: 1584) {
            _ = try analyzer.process(TestSignal.samples(startFrame: start, count: 1584), startingAt: Double(start) / 48000)
        }
        let result = try analyzer.process(TestSignal.samples(startFrame: 0, count: 1584), startingAt: 100)
        XCTAssertEqual(context.resets, 1)
        XCTAssertNil(result.reading.pulseMilliseconds)
    }
}

private final class ClickContext: AudioContentClassifying {
    var permission: AudioContentPermission = [.speechClear]
    var resets = 0
    func process(_ samples: [Float]) throws -> AudioContentPermission { permission }
    func reset(rate: Double) throws { resets += 1 }
    func stop() {}
}
