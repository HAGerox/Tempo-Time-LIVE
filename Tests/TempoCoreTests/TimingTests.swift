import XCTest
@testable import TempoCore

final class TimingTests: XCTestCase {
    func testPulseFractionsDoNotDependOnNoteInterpretation() {
        for unit in ClickUnit.allCases {
            let rows = NoteTiming.rows(pulseMilliseconds: 500, basis: .pulse, clickUnit: unit, modifier: .straight)
            XCTAssertEqual(rows.first { $0.denominator == 8 }?.milliseconds, 62.5)
            XCTAssertEqual(rows.first { $0.denominator == 128 }?.milliseconds, 3.90625)
        }
    }
    func testQuarterVersusEighthClickChangesNamedNotesAndBPM() {
        XCTAssertEqual(NoteTiming.quarterBPM(pulseMilliseconds: 500, clickUnit: .quarter), 120)
        XCTAssertEqual(NoteTiming.quarterBPM(pulseMilliseconds: 500, clickUnit: .eighth), 60)
        let quarters = NoteTiming.rows(pulseMilliseconds: 500, basis: .notes, clickUnit: .quarter, modifier: .straight)
        let eighths = NoteTiming.rows(pulseMilliseconds: 500, basis: .notes, clickUnit: .eighth, modifier: .straight)
        XCTAssertEqual(quarters.first { $0.denominator == 32 }?.milliseconds, 62.5)
        XCTAssertEqual(eighths.first { $0.denominator == 32 }?.milliseconds, 125)
    }
    func testCompoundBeatAndAllModifiers() {
        XCTAssertEqual(NoteTiming.quarterBPM(pulseMilliseconds: 500, clickUnit: .dottedQuarter), 180)
        for unit in ClickUnit.allCases {
            for modifier in NoteModifier.allCases {
                for row in NoteTiming.rows(pulseMilliseconds: 500, basis: .notes, clickUnit: unit, modifier: modifier) {
                    XCTAssertEqual(row.milliseconds, 500 * 4 / unit.quarterNotes / Double(row.denominator) * modifier.multiplier, accuracy: 1e-9)
                }
            }
        }
    }
    func testInvalidTimingInputs() {
        for invalid in [0.0, -1, .infinity, .nan] {
            XCTAssertNil(NoteTiming.quarterBPM(pulseMilliseconds: invalid, clickUnit: .quarter))
            XCTAssertTrue(NoteTiming.rows(pulseMilliseconds: invalid, basis: .notes, clickUnit: .quarter, modifier: .straight).isEmpty)
        }
    }
    func testTempoPrecisionIsNotRoundedBeforeConverting() {
        let pulse = 60_000 / 123.456
        let row = NoteTiming.rows(pulseMilliseconds: pulse, basis: .notes, clickUnit: .quarter, modifier: .dotted)[5]
        XCTAssertEqual(row.milliseconds, 91.1255832037, accuracy: 0.000001)
    }
}

final class TrackerTests: XCTestCase {
    private func steady(_ interval: Double = 0.5) -> TempoTracker {
        var tracker = TempoTracker()
        for i in 0...8 { tracker.addOnset(at: Double(i) * interval) }
        return tracker
    }
    func testFirstAndSecondTap() {
        var t = TempoTracker()
        XCTAssertNil(t.reading(at: 0).pulseMilliseconds)
        t.addOnset(at: 0)
        XCTAssertNil(t.reading(at: 0).pulseMilliseconds)
        t.addOnset(at: 0.5)
        XCTAssertEqual(t.reading(at: 0.5).pulseMilliseconds, 500)
        XCTAssertFalse(t.reading(at: 0.5).isStable)
    }
    func testLocksAfterFourIntervals() {
        var t = TempoTracker()
        for i in 0...4 { t.addOnset(at: Double(i) / 2) }
        XCTAssertTrue(t.reading(at: 2).isStable)
    }
    func testBounceDoesNotMoveAnchor() {
        var t = steady()
        t.addOnset(at: 4.03); t.addOnset(at: 4.5)
        XCTAssertEqual(t.reading(at: 4.5).pulseMilliseconds, 500)
        XCTAssertEqual(t.reading(at: 4.5).pulseCount, 10)
    }
    func testExtraHalfwayPulseDoesNotDoubleTempo() {
        var t = steady()
        for time in [4.25, 4.5, 5.0] { t.addOnset(at: time) }
        XCTAssertEqual(t.reading(at: 5).pulseMilliseconds, 500)
        XCTAssertTrue(t.reading(at: 5).isStable)
    }
    func testDroppedClickDoesNotHalveTempo() {
        var t = steady()
        t.addOnset(at: 5)
        XCTAssertTrue(t.reading(at: 5).isChanging)
        t.addOnset(at: 5.5)
        XCTAssertEqual(t.reading(at: 5.5).pulseMilliseconds, 500)
        XCTAssertTrue(t.reading(at: 5.5).isStable)
    }
    func testRealTempoChangeIncludingHalfAndDouble() {
        for interval in [0.25, 0.4, 0.75, 1.0] {
            var t = steady()
            for i in 1...3 { t.addOnset(at: 4 + Double(i) * interval) }
            XCTAssertEqual(t.reading(at: 4 + 3 * interval).pulseMilliseconds!, interval * 1000, accuracy: 1e-8)
            XCTAssertFalse(t.reading(at: 4 + 3 * interval).isChanging)
        }
    }
    func testStaleReadingAndResetAfterPause() {
        var t = steady()
        XCTAssertTrue(t.reading(at: 7).isStale)
        XCTAssertFalse(t.reading(at: 7).isStable)
        t.addOnset(at: 9)
        XCTAssertNil(t.reading(at: 9).pulseMilliseconds)
        t.addOnset(at: 9.6)
        XCTAssertEqual(t.reading(at: 9.6).pulseMilliseconds!, 600, accuracy: 1e-8)
    }
    func testSlowAndFastLimitsWithoutOctaveFolding() {
        for interval in [0.1, 3.0] {
            let t = steady(interval)
            XCTAssertEqual(t.reading(at: interval * 8).pulseMilliseconds!, interval * 1000, accuracy: 1e-7)
            XCTAssertTrue(t.reading(at: interval * 8).isStable)
        }
    }
    func testOutOfOrderAndNonFiniteTimestampsIgnored() {
        var t = steady()
        for time in [3.0, 4.0, Double.nan, Double.infinity] { t.addOnset(at: time) }
        t.addOnset(at: 4.5)
        XCTAssertEqual(t.reading(at: 4.5).pulseMilliseconds, 500)
    }
    func testJitterIsReported() {
        var t = TempoTracker()
        var time = 0.0
        t.addOnset(at: time)
        for delta in [0.501, 0.499, 0.502, 0.498, 0.5, 0.5] { time += delta; t.addOnset(at: time) }
        XCTAssertEqual(t.reading(at: time).pulseMilliseconds!, 500, accuracy: 1e-7)
        XCTAssertGreaterThan(t.reading(at: time).jitterMilliseconds, 1)
        XCTAssertTrue(t.reading(at: time).isStable)
    }
}
