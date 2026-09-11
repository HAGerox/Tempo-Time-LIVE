import XCTest
import TempoCore
@testable import TempoInput

final class SoundContentAnalyzerTests: XCTestCase {
    func testRealClassifierFixturesAndReset() throws {
        guard let folder = ProcessInfo.processInfo.environment["TEMPO_CONTENT_FIXTURES"] else {
            throw XCTSkip("Set TEMPO_CONTENT_FIXTURES to local music-, speech-, click-, noise-, tone- and silence WAV fixtures")
        }
        let files = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "wav" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(files.isEmpty)
        let classifier = try SoundContentAnalyzer(rate: 48000)
        defer { classifier.stop() }
        for file in files {
            let wave = try WaveFile(data: Data(contentsOf: file))
            try classifier.reset(rate: wave.sampleRate)
            XCTAssertEqual(try classifier.process([]), [])
            var music = 0, clicks = 0, blocks = 0
            var clickDetector = SparseClickAnalyzer(sampleRate: wave.sampleRate)
            var emptyAnalyzer = ClickAnalyzer(sampleRate: wave.sampleRate)
            let empty = emptyAnalyzer.process([], startingAt: 0)
            var clickReadings = 0
            let source = try wave.samples(channel: 0, frames: 0..<wave.frameCount)
            XCTAssertFalse(source.isEmpty, file.lastPathComponent)
            guard !source.isEmpty else { continue }
            // Short noise recordings must run long enough that a false tempo
            // could actually acquire after classification. Repeat them to 12 s.
            let frameCount = max(source.count, Int(wave.sampleRate * 12))
            var tempos: [Double] = []
            for offset in stride(from: 0, to: frameCount, by: 1584) {
                let samples = (offset..<min(offset + 1584, frameCount)).map { source[$0 % source.count] }
                let result = try classifier.process(samples)
                if result.contains(.music) { music += 1 }
                if result.contains(.speechClear) { clicks += 1 }
                if result.contains(.speechClear) {
                    let snapshot = clickDetector.process(samples, startingAt: Double(offset) / wave.sampleRate, music: empty)
                    if let bpm = snapshot.reading.pulsesPerMinute { clickReadings += 1; tempos.append(bpm) }
                } else {
                    clickDetector = SparseClickAnalyzer(sampleRate: wave.sampleRate)
                }
                blocks += 1
                // Let the native asynchronous observer keep up while running much
                // faster than real time; no microphone or speaker is involved.
                Thread.sleep(forTimeInterval: 0.001)
            }
            if file.lastPathComponent.hasPrefix("music-") {
                XCTAssertGreaterThan(music, blocks / 2, file.lastPathComponent)
            } else if file.lastPathComponent.hasPrefix("click-") {
                XCTAssertGreaterThan(clicks, blocks / 2, file.lastPathComponent)
                XCTAssertGreaterThan(clickReadings, 0, file.lastPathComponent)
                if let expected = ProcessInfo.processInfo.environment["TEMPO_CONTENT_CLICK_BPM"].flatMap(Double.init),
                   !tempos.isEmpty {
                    XCTAssertEqual(tempos.sorted()[tempos.count / 2], expected, accuracy: 1, file.lastPathComponent)
                }
            } else {
                XCTAssertEqual(music, 0, file.lastPathComponent)
                XCTAssertEqual(clickReadings, 0, file.lastPathComponent)
                if file.lastPathComponent.hasPrefix("speech-") {
                    XCTAssertEqual(clicks, 0, file.lastPathComponent)
                }
                // Broad environmental tests intentionally expose residual false readings
                // when the user selects Click track for a non-click source.
            }
            print("Content gate: \(file.lastPathComponent), music \(music)/\(blocks), clicks \(clicks)/\(blocks), click readings \(clickReadings)")
        }
        classifier.stop()
        XCTAssertThrowsError(try classifier.process([0]))
        try classifier.reset(rate: 44100)
        XCTAssertEqual(try classifier.process([0]), [], "Restart cannot reuse old classification evidence")
    }
}
