import XCTest
@testable import TempoCore

final class TempoLockTests: XCTestCase {
    private let source = TempoReading(pulseMilliseconds: 500, intervalCount: 8,
        jitterMilliseconds: 0, isStable: true, isStale: false, isChanging: false, pulseCount: 20)

    func testJitterAndBriefOctaveErrorsDoNotMoveLock() throws {
        var lock = TempoLock()
        lock.observe(bpm: 120, at: 0)
        for step in 1...60 {
            let bpm = step % 10 < 3 ? 60.0 : (step % 2 == 0 ? 119.2 : 120.8)
            lock.observe(bpm: bpm, at: Double(step) * 0.5)
            XCTAssertEqual(try XCTUnwrap(lock.reading(at: Double(step) * 0.5, source: source).pulsesPerMinute), 120, accuracy: 0.5)
        }
    }

    func testSustainedChangesCommitWithoutAveragingTempos() throws {
        for newBPM in [90.0, 60.0, 240.0] {
            var lock = TempoLock()
            lock.observe(bpm: 120, at: 0)
            let duration = newBPM == 90 ? 3.0 : 5.0
            for step in 1...Int((duration + 0.5) * 2) {
                let time = Double(step) * 0.5
                let accepted = lock.observe(bpm: newBPM, at: time)
                let committed = time >= duration + 0.5
                XCTAssertEqual(accepted, committed)
                XCTAssertEqual(try XCTUnwrap(lock.reading(at: time, source: source).pulsesPerMinute), committed ? newBPM : 120, accuracy: 0.001)
            }
        }
    }

    func testDuplicateAndOutOfOrderEvidenceCannotConfirmOrKeepAlive() {
        var lock = TempoLock()
        lock.observe(bpm: 120, at: 0)
        lock.observe(bpm: 60, at: 0.5)
        for _ in 0..<1000 {
            XCTAssertFalse(lock.observe(bpm: 60, at: 0.5))
            XCTAssertFalse(lock.observe(bpm: 60, at: 0.4))
        }
        XCTAssertNil(lock.reading(at: 4, source: source).pulsesPerMinute)
    }

    func testReviewCreditsSupportedAudioOnceButRequiresFreshReviews() throws {
        var lock = TempoLock()
        lock.observe(bpm: 120, at: 0)
        XCTAssertFalse(lock.observe(bpm: 60, at: 5, supportedSince: 1))
        for _ in 0..<100 { XCTAssertFalse(lock.observe(bpm: 60, at: 5, supportedSince: 1)) }
        XCTAssertFalse(lock.observe(bpm: 60, at: 6, supportedSince: 1))
        XCTAssertEqual(try XCTUnwrap(lock.reading(at: 6, source: source).pulsesPerMinute), 120, accuracy: 0.001)
        XCTAssertTrue(lock.observe(bpm: 60, at: 7, supportedSince: 1))
        XCTAssertEqual(try XCTUnwrap(lock.reading(at: 7, source: source).pulsesPerMinute), 60, accuracy: 0.001)
    }

    func testUnsupportedGapDoesNotConfirmCandidate() throws {
        var lock = TempoLock()
        lock.observe(bpm: 120, at: 0)
        lock.observe(bpm: 60, at: 0.5)
        lock.observe(bpm: 60, at: 1)
        lock.observe(bpm: 60, at: 5)
        XCTAssertFalse(lock.observe(bpm: 60, at: 5.5))
        XCTAssertEqual(try XCTUnwrap(lock.reading(at: 5.5, source: source).pulsesPerMinute), 120, accuracy: 0.001)
    }

    func testResetAndExpiredEvidenceAllowFreshAcquisition() {
        var lock = TempoLock()
        lock.observe(bpm: 120, at: 0)
        lock.reset()
        XCTAssertNil(lock.reading(at: 0, source: source).pulsesPerMinute)
        XCTAssertTrue(lock.observe(bpm: 60, at: 0))
        XCTAssertTrue(lock.observe(bpm: 180, at: 20))
    }

    func testGradualRampFollowsWithoutOctaveLockout() throws {
        var lock = TempoLock()
        for step in 0...120 {
            lock.observe(bpm: 120 + Double(step) / 10, at: Double(step) * 0.5)
        }
        let result = try XCTUnwrap(lock.reading(at: 60, source: source).pulsesPerMinute)
        XCTAssertGreaterThan(result, 130)
        XCTAssertLessThanOrEqual(result, 132)
    }

    func testInconsistentCandidatesNeverAccumulateConfirmation() throws {
        var lock = TempoLock()
        lock.observe(bpm: 120, at: 0)
        for step in 1...30 {
            lock.observe(bpm: step % 2 == 0 ? 90 : 100, at: Double(step) * 0.5)
        }
        XCTAssertNil(lock.reading(at: 15, source: source).pulsesPerMinute, "Conflicting evidence must not hold an unsupported BPM forever")
        XCTAssertFalse(lock.observe(bpm: .nan, at: 16))
        XCTAssertFalse(lock.observe(bpm: 0, at: 16))
        XCTAssertFalse(lock.observe(bpm: 120, at: .infinity))
    }
}
