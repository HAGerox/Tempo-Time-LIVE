import XCTest
@testable import TempoCore

final class SongBeatTests: XCTestCase {
    func locked() -> SongBeatTracker {
        var tracker = SongBeatTracker()
        for i in 0..<5 { tracker.addBeat(at: Double(i) * 0.5, strength: 0.8) }
        return tracker
    }

    func testRequiresConsistentStrongEvidence() {
        var tracker = SongBeatTracker()
        for time in [0.0, 0.5, 1, 1.5] { tracker.addBeat(at: time, strength: 0.9) }
        XCTAssertNil(tracker.reading(at: 1.5).pulseMilliseconds)
        XCTAssertTrue(tracker.addBeat(at: 2, strength: 0.8))
        XCTAssertEqual(tracker.reading(at: 2).pulseMilliseconds!, 500, accuracy: 0.01)
        tracker.reset()
        for i in 0..<12 { tracker.addBeat(at: Double(i) * 0.5, strength: 0.45) }
        XCTAssertNil(tracker.reading(at: 6).pulseMilliseconds)
        tracker.reset()
        for time in [0.0, 0.3, 1, 1.2, 2.1, 2.4] { tracker.addBeat(at: time, strength: 0.9) }
        XCTAssertNil(tracker.reading(at: 2.4).pulseMilliseconds)
    }

    func testMissingBeatKeepsTempoAndHoldoverExpires() {
        var tracker = locked()
        XCTAssertEqual(tracker.status(at: 2.9, silent: false), "Following")
        XCTAssertTrue(tracker.addBeat(at: 3, strength: 0.8))
        XCTAssertEqual(tracker.reading(at: 3).pulseMilliseconds!, 500, accuracy: 0.01)
        tracker.advance(to: 4.6)
        XCTAssertNil(tracker.reading(at: 4.6).pulseMilliseconds)
        XCTAssertEqual(tracker.status(at: 4.6, silent: false), "Listening")
        XCTAssertFalse(tracker.addBeat(at: 4.7, strength: 0.9))
    }

    func testOffbeatDoesNotSteerButNewRhythmCanAcquire() {
        var tracker = locked()
        XCTAssertFalse(tracker.addBeat(at: 2.25, strength: 0.9))
        XCTAssertEqual(tracker.lastBeat, 2)
        XCTAssertTrue(tracker.addBeat(at: 2.5, strength: 0.8))
        // A sustained new tempo needs its own supporting pattern.
        for time in [2.9, 3.3, 3.7, 4.1, 4.5, 4.9, 5.3] {
            tracker.addBeat(at: time, strength: 0.9)
        }
        XCTAssertEqual(tracker.reading(at: 5.3).pulseMilliseconds!, 400, accuracy: 5)
    }

    func testWeakEvidenceCannotMaintainAnOldLockForever() {
        var tracker = locked()
        for i in 5..<20 {
            tracker.addBeat(at: Double(i) * 0.5, strength: 0.41)
            tracker.advance(to: Double(i) * 0.5)
        }
        XCTAssertNil(tracker.reading(at: 9.5).pulseMilliseconds)
    }

    func testFrameQuantizationAndGradualTempoMovement() {
        var tracker = SongBeatTracker()
        for i in 0..<16 {
            tracker.addBeat(at: (Double(i) * 60 / 136 / 0.02).rounded() * 0.02, strength: 0.8)
        }
        XCTAssertEqual(tracker.reading(at: 6.62).pulsesPerMinute!, 136, accuracy: 2)
        tracker.reset()
        XCTAssertEqual(tracker.status(at: 7, silent: true), "No signal")
        XCTAssertNil(tracker.reading(at: 7).pulseMilliseconds)
        XCTAssertFalse(tracker.addBeat(at: 7.1, strength: .nan))
    }
}
