import XCTest
import TempoCore
@testable import TempoInput

final class SongAnalyzerTests: XCTestCase {
    func testContentGateClearsMusicAndRejectsOldReviewOnReturn() throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let reply = "{\"beats\":[0,0.3,0.6,0.9,1.2],\"strengths\":[0.9,0.9,0.9,0.9,0.9],\"silent\":false,\"reset\":false,\"review\":{\"period\":0.6,\"beat\":1.1,\"quality\":0.8,\"id\":1}}"
        let contents = "#!/bin/sh\nread line\necho '{\"ready\":true,\"frameOffsetSeconds\":0.04,\"backgroundReview\":true}'\nwhile read line; do echo '\(reply)'; done\n"
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        defer { try? FileManager.default.removeItem(at: script) }
        let classifier = StubContentClassifier()
        let analyzer = try SongAnalyzer(executable: script.path, rate: 48000, cancelled: { false }, classifier: classifier)
        defer { analyzer.stop() }
        let music = try analyzer.process([Float](repeating: 0.1, count: 60000), startingAt: 100)
        XCTAssertNotNil(music.reading.pulseMilliseconds)
        classifier.permission = []
        let speech = try analyzer.process([Float](repeating: 0.1, count: 1584), startingAt: 101.25)
        XCTAssertNil(speech.reading.pulseMilliseconds)
        XCTAssertNil(speech.lastBeatTime)
        XCTAssertEqual(speech.detectedOnsets, 0)
        XCTAssertEqual(speech.peakDB, -20, accuracy: 0.001, "The input meter remains live")
        classifier.permission = [.music]
        let returning = try analyzer.process([Float](repeating: 0.1, count: 1584), startingAt: 101.283)
        XCTAssertNil(returning.reading.pulseMilliseconds, "A previous music review cannot reappear after speech")
        XCTAssertNil(returning.lastBeatTime)
    }

    func testMusicModeNeverFallsBackToClicks() throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let contents = "#!/bin/sh\nread line\necho '{\"ready\":true}'\nwhile read line; do echo '{\"beats\":[],\"strengths\":[],\"silent\":false,\"reset\":false}'; done\n"
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        defer { try? FileManager.default.removeItem(at: script) }
        let classifier = StubContentClassifier()
        classifier.permission = [.speechClear]
        let analyzer = try SongAnalyzer(executable: script.path, rate: 48000, cancelled: { false }, classifier: classifier)
        defer { analyzer.stop() }
        var last: AnalysisSnapshot?
        for offset in stride(from: 0, to: 48000 * 4, by: 24000) {
            last = try analyzer.process(TestSignal.samples(startFrame: offset, count: 24000), startingAt: Double(offset) / 48000)
        }
        XCTAssertNil(last?.reading.pulsesPerMinute, "Non-speech clicks must not enable a fallback in Music mode")
        classifier.permission = []
        let speech = try analyzer.process(TestSignal.samples(startFrame: 192000, count: 24000), startingAt: 4)
        XCTAssertNil(speech.reading.pulseMilliseconds)
        XCTAssertNil(speech.lastBeatTime)
        XCTAssertEqual(speech.detectedOnsets, 0)
    }

    func testBackgroundReviewUsesAudioTimeAndReturnsToWarmForeground() throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let contents = """
        #!/bin/sh
        read line
        echo '{"ready":true,"frameOffsetSeconds":0.04,"backgroundReview":true}'
        read line
        echo '{"beats":[0,0.3,0.6,0.9,1.2],"strengths":[0.9,0.9,0.9,0.9,0.9],"silent":false,"reset":false,"review":{"period":0.6,"beat":1.1,"quality":0.8,"id":1}}'
        read line
        echo '{"beats":[],"strengths":[],"silent":false,"reset":false,"review":{"period":0.6,"beat":1.1,"quality":0.8,"id":1}}'
        read line
        echo '{"beats":[],"strengths":[],"silent":false,"reset":false,"review":null}'
        read line
        echo '{"beats":[],"strengths":[],"silent":true,"reset":true,"review":null}'
        while read line; do :; done
        """
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        defer { try? FileManager.default.removeItem(at: script) }
        let analyzer = try SongAnalyzer(executable: script.path, rate: 48000, cancelled: { false }, classifier: StubContentClassifier())
        defer { analyzer.stop() }
        let reviewed = try analyzer.process([Float](repeating: 0.1, count: 60000), startingAt: 100)
        XCTAssertEqual(try XCTUnwrap(reviewed.reading.pulseMilliseconds), 600, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(reviewed.lastBeatTime), 101.1, accuracy: 0.001)
        let repeated = try analyzer.process([Float](repeating: 0.1, count: 4800), startingAt: 101.25)
        XCTAssertNil(repeated.lastBeatTime, "The same historical result must not renew phase evidence")
        XCTAssertEqual(repeated.detectedOnsets, 0)
        let foreground = try analyzer.process([Float](repeating: 0.1, count: 4800), startingAt: 101.35)
        XCTAssertEqual(try XCTUnwrap(foreground.reading.pulseMilliseconds), 300, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(foreground.lastBeatTime), 101.16, accuracy: 0.001)
        let silent = try analyzer.process([Float](repeating: 0, count: 4800), startingAt: 101.45)
        XCTAssertNil(silent.reading.pulseMilliseconds)
    }

    func testBackgroundReviewCannotSupplyFutureBeat() throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let contents = """
        #!/bin/sh
        read line
        echo '{"ready":true,"backgroundReview":true}'
        read line
        echo '{"beats":[],"strengths":[],"silent":false,"reset":false,"review":{"period":0.6,"beat":20,"quality":0.8,"id":1}}'
        while read line; do :; done
        """
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        defer { try? FileManager.default.removeItem(at: script) }
        let analyzer = try SongAnalyzer(executable: script.path, rate: 48000, cancelled: { false }, classifier: StubContentClassifier())
        defer { analyzer.stop() }
        XCTAssertThrowsError(try analyzer.process([Float](repeating: 0.1, count: 4800), startingAt: 100))
    }

    func testRealMusicLockSilenceAndRestart() throws {
        let env = ProcessInfo.processInfo.environment
        guard let worker = env["TEMPO_TEST_BEATNET_WORKER"],
              let fixture = env["TEMPO_TEST_SONG"],
              let expected = env["TEMPO_TEST_BPM"].flatMap(Double.init) else {
            throw XCTSkip("Set TEMPO_TEST_BEATNET_WORKER, TEMPO_TEST_SONG and TEMPO_TEST_BPM for real model integration")
        }
        let wave = try WaveFile(data: Data(contentsOf: URL(fileURLWithPath: fixture)))
        let analyzer = try SongAnalyzer(executable: worker, rate: wave.sampleRate, cancelled: { false })
        defer { analyzer.stop() }
        var frame = 0
        var tempos: [Double] = []
        var previousBeat = -Double.infinity
        for offset in stride(from: 0, to: wave.frameCount, by: 1584) {
            let pcm = try wave.samples(channel: 0, frames: offset..<min(offset + 1584, wave.frameCount))
            let result = try analyzer.process(pcm, startingAt: 1000 + Double(frame) / wave.sampleRate)
            frame += pcm.count
            if let bpm = result.reading.pulsesPerMinute { tempos.append(bpm) }
            if let beat = result.lastBeatTime {
                XCTAssertGreaterThan(beat, previousBeat)
                XCTAssertLessThanOrEqual(beat, 1000 + Double(frame) / wave.sampleRate)
                XCTAssertGreaterThan(beat, 999)
                previousBeat = beat
            }
        }
        if expected == 0 {
            XCTAssertTrue(tempos.isEmpty, "Nonmusical fixture must not establish a tempo")
        } else {
            XCTAssertGreaterThan(tempos.count, 100, "Music should acquire and sustain a visible lock")
        }
        if !tempos.isEmpty {
            let sorted = tempos.sorted()
            XCTAssertEqual(sorted[sorted.count / 2], expected, accuracy: 8)
            print("Song lock: \(tempos.count) blocks, median \(sorted[sorted.count / 2]) BPM")
        }
        for _ in 0..<Int(wave.sampleRate / 1584) + 1 {
            let result = try analyzer.process([Float](repeating: 0, count: 1584), startingAt: 1000 + Double(frame) / wave.sampleRate)
            frame += 1584
            if Double(frame - wave.frameCount) / wave.sampleRate > 0.7 {
                XCTAssertNil(result.reading.pulseMilliseconds)
                XCTAssertNil(result.lastBeatTime)
                XCTAssertEqual(result.songStatus, "No signal")
            }
        }
        let restart = try analyzer.process(wave.samples(channel: 0, frames: 0..<1584), startingAt: 1000 + Double(frame) / wave.sampleRate)
        XCTAssertNil(restart.reading.pulseMilliseconds, "A new song must acquire its own lock")
    }

    func testAudioTimestampAndSilenceCrossWorkerProtocol() throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let contents = """
        #!/bin/sh
        read line
        echo '{"ready":true,"frameOffsetSeconds":0.04}'
        read line
        echo '{"beats":[0,0.3,0.6,0.9,1.2],"strengths":[0.9,0.9,0.9,0.9,0.9],"silent":false,"reset":false}'
        read line
        echo '{"beats":[],"strengths":[],"silent":true,"reset":true}'
        while read line; do :; done
        """
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        defer { try? FileManager.default.removeItem(at: script) }
        let analyzer = try SongAnalyzer(executable: script.path, rate: 48000, cancelled: { false }, classifier: StubContentClassifier())
        defer { analyzer.stop() }
        let locked = try analyzer.process([Float](repeating: 0.1, count: 60000), startingAt: 100)
        XCTAssertEqual(try XCTUnwrap(locked.lastBeatTime), 101.2 - 0.04, accuracy: 0.000001)
        XCTAssertEqual(locked.songStatus, "Tracking")
        XCTAssertEqual(locked.detectedOnsets, 1)
        let silent = try analyzer.process([Float](repeating: 0, count: 24000), startingAt: 101.25)
        XCTAssertNil(silent.reading.pulseMilliseconds)
        XCTAssertNil(silent.lastBeatTime)
        XCTAssertEqual(silent.songStatus, "No signal")
    }

    func testResetReusesWorkerAndClearsStreamClock() throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let contents = """
        #!/bin/sh
        read line
        echo '{"ready":true}'
        read line
        echo '{"beats":[0,0.3,0.6,0.9,1.2],"strengths":[0.9,0.9,0.9,0.9,0.9],"silent":false,"reset":false}'
        read line
        echo '{"ready":true}'
        read line
        echo '{"beats":[],"strengths":[],"silent":true,"reset":false}'
        read line
        echo '{"beats":[0,0.3,0.6,0.9,1.2],"strengths":[0.9,0.9,0.9,0.9,0.9],"silent":false,"reset":false}'
        while read line; do :; done
        """
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        defer { try? FileManager.default.removeItem(at: script) }
        var cancelled = false
        let analyzer = try SongAnalyzer(executable: script.path, rate: 48000, cancelled: { cancelled }, classifier: StubContentClassifier())
        defer { analyzer.stop() }
        // An in-flight PCM exchange finishes even when selection invalidates its token.
        cancelled = true
        let old = try analyzer.process([Float](repeating: 0.1, count: 60000), startingAt: 100)
        XCTAssertNotNil(old.reading.pulseMilliseconds)
        cancelled = true
        try analyzer.reset(rate: 44100, cancelled: { false })
        let empty = try analyzer.process([Float](repeating: 0, count: 441), startingAt: 200)
        XCTAssertNil(empty.reading.pulseMilliseconds)
        let new = try analyzer.process([Float](repeating: 0.1, count: 55000), startingAt: 200.01)
        XCTAssertEqual(try XCTUnwrap(new.lastBeatTime), 201.2 - 529.0 / 22050, accuracy: 0.000001)
    }

    func testNumericalThreadLimitsReachChildBeforeStartup() throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let contents = """
        #!/bin/sh
        for value in "$OPENBLAS_NUM_THREADS" "$OMP_NUM_THREADS" "$MKL_NUM_THREADS" "$VECLIB_MAXIMUM_THREADS" "$NUMEXPR_NUM_THREADS" "$BLIS_NUM_THREADS"; do
          [ "$value" = "1" ] || exit 1
        done
        [ "$OMP_WAIT_POLICY" = "PASSIVE" ] || exit 1
        read line
        echo '{"ready":true}'
        read line
        """
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        defer { try? FileManager.default.removeItem(at: script) }
        let analyzer = try SongAnalyzer(executable: script.path, rate: 48000, cancelled: { false }, classifier: StubContentClassifier())
        analyzer.stop()
    }

    func testExitedWorkerFailsInsteadOfFallingBack() {
        XCTAssertThrowsError(try SongAnalyzer(executable: "/usr/bin/false", rate: 48000, cancelled: { false }, classifier: StubContentClassifier()))
    }

    func testInvalidHandshakeIsRejected() {
        XCTAssertThrowsError(try SongAnalyzer(executable: "/bin/cat", rate: 48000, cancelled: { false }, classifier: StubContentClassifier()))
    }

    func testCancellationInterruptsUnresponsiveModelStartup() throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "#!/bin/sh\nwhile read line; do :; done\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        defer { try? FileManager.default.removeItem(at: script) }
        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try SongAnalyzer(executable: script.path, rate: 48000,
            cancelled: { ProcessInfo.processInfo.systemUptime - start > 0.2 }, classifier: StubContentClassifier()))
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2)
    }
}

// Protocol tests supply known content; real audio integration uses SoundAnalysis.
private final class StubContentClassifier: AudioContentClassifying {
    var permission: AudioContentPermission = [.music, .speechClear]
    func process(_ samples: [Float]) throws -> AudioContentPermission { permission }
    func reset(rate: Double) throws {}
    func stop() {}
}
