import XCTest
@testable import TempoCore

final class AudioContentGateTests: XCTestCase {
    func testSpeechClosesMusicAndSpeechVeto() {
        var gate = AudioContentGate()
        for time in [1.5, 2.0] { gate.update(.init(end: time, music: 0.8, speech: 0.1)) }
        XCTAssertEqual(gate.permissions(at: 2), [.music, .speechClear])
        gate.update(.init(end: 2.5, music: 0.1, speech: 0.9))
        XCTAssertEqual(gate.permissions(at: 2.5), [])
        gate.update(.init(end: 3, music: 0.8, speech: 0.1))
        XCTAssertEqual(gate.permissions(at: 3), [])
        gate.update(.init(end: 3.5, music: 0.8, speech: 0.1))
        XCTAssertEqual(gate.permissions(at: 3.5), [.music, .speechClear])
    }

    func testMusicRequiresConfirmationAndSurvivesVocalsAndQuietPassage() {
        var gate = AudioContentGate()
        gate.update(.init(end: 1.5, music: 0.8, speech: 0.6))
        XCTAssertEqual(gate.permissions(at: 1.5), [])
        gate.update(.init(end: 2, music: 0.8, speech: 0.6))
        XCTAssertEqual(gate.permissions(at: 2), [.music])
        gate.update(.init(end: 2.5, music: 0.4, speech: 0.6))
        XCTAssertEqual(gate.permissions(at: 2.5), [.music])
        gate.update(.init(end: 3, music: 0.2, speech: 0.1))
        XCTAssertTrue(gate.permissions(at: 3).contains(.music))
        gate.update(.init(end: 3.5, music: 0.2, speech: 0.1))
        XCTAssertFalse(gate.permissions(at: 3.5).contains(.music))
    }

    func testUnknownNonSpeechDoesNotEnableMusic() {
        var gate = AudioContentGate()
        for time in [1.5, 2.0] { gate.update(.init(end: time, music: 0.1, speech: 0.1)) }
        // This bit only removes a veto in explicitly selected Click track mode.
        // The caller must independently detect stable pulses; there is no click class.
        XCTAssertEqual(gate.permissions(at: 2), [.speechClear])
    }

    func testStaleResultsNeedFreshConfirmation() {
        var gate = AudioContentGate()
        for time in [1.5, 2.0] { gate.update(.init(end: time, music: 0.8, speech: 0)) }
        XCTAssertEqual(gate.permissions(at: 3.6), [])
        gate.update(.init(end: 4, music: 0.8, speech: 0))
        XCTAssertEqual(gate.permissions(at: 4), [])
    }

    func testDuplicateOldAndInvalidEvidenceCannotOpenGate() {
        var gate = AudioContentGate()
        gate.update(.init(end: 1.5, music: 0.8, speech: 0))
        gate.update(.init(end: 1.5, music: 0.8, speech: 0))
        gate.update(.init(end: 1, music: 0.8, speech: 0))
        gate.update(.init(end: 2, music: .nan, speech: 0))
        XCTAssertEqual(gate.permissions(at: 2), [])
        gate.reset()
        XCTAssertEqual(gate.permissions(at: 2), [])
    }
}
