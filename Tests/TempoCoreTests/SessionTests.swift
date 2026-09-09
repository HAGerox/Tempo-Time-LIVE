import XCTest
@testable import TempoCore

final class SessionTests: XCTestCase {
    func testTapOverridesAudioAndReturnsAfterThirtySeconds() {
        var audio = TempoTracker()
        for i in 0...8 { audio.addOnset(at: Double(i) * 0.5) }
        var session = TempoSession()
        session.audioReading = audio.reading(at: 4)
        session.tap(at: 10)
        XCTAssertTrue(session.isManual(at: 10))
        XCTAssertNil(session.reading(at: 10)?.pulseMilliseconds)
        session.tap(at: 11)
        XCTAssertEqual(session.reading(at: 11)?.pulseMilliseconds, 1000)
        XCTAssertEqual(session.reading(at: 40.999)?.pulseMilliseconds, 1000)
        XCTAssertFalse(session.isManual(at: 41))
        XCTAssertEqual(session.reading(at: 41)?.pulseMilliseconds, 500)
    }

    func testMoreTapsExtendOverrideAndRestartAfterExpiry() {
        var session = TempoSession()
        session.tap(at: 0); session.tap(at: 0.5); session.tap(at: 1)
        XCTAssertTrue(session.isManual(at: 30.9))
        XCTAssertFalse(session.isManual(at: 31))
        session.tap(at: 32)
        XCTAssertNil(session.reading(at: 32)?.pulseMilliseconds)
        session.tap(at: 32.5)
        XCTAssertEqual(session.reading(at: 32.5)?.pulseMilliseconds, 500)
    }

    func testReturnToAudioUsesCurrentReadingAndNoAudioIsEmpty() {
        var session = TempoSession()
        session.tap(at: 0); session.tap(at: 0.5)
        XCTAssertNil(session.reading(at: 30.5))
        var audio = TempoTracker()
        audio.addOnset(at: 29); audio.addOnset(at: 29.75)
        session.audioReading = audio.reading(at: 30)
        XCTAssertEqual(session.reading(at: 30.5)?.pulseMilliseconds, 750)
    }
}
