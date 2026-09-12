import XCTest
import TempoCore
@testable import TempoInput

/// Replay exactly the same recorded model replies through either revision's bridge.
/// Record with scripts/record-tempo-evidence.py; fixtures remain outside version control.
final class TempoEvidenceReplayTests: XCTestCase {
    func testRecordedEvidence() throws {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["TEMPO_TEST_EVIDENCE"] else {
            throw XCTSkip("Set TEMPO_TEST_EVIDENCE to a directory of recorded model replies")
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: directory).filter { $0.hasSuffix(".json") }.sorted()
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let data = try Data(contentsOf: URL(fileURLWithPath: directory).appendingPathComponent(file))
            let trace = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let rate = try XCTUnwrap(trace["rate"] as? Double)
            let blocks = try XCTUnwrap(trace["blocks"] as? [[String: Any]])
            let script = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            var commands = "#!/bin/sh\n"
            for reply in [trace["handshake"]!] + blocks.map({ $0["response"]! }) {
                let json = String(data: try JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys]), encoding: .utf8)!
                commands += "read line || exit 0\nprintf '%s\\n' '\(json.replacingOccurrences(of: "'", with: "'\\''"))'\n"
            }
            commands += "while read line; do :; done\n"
            try commands.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            defer { try? FileManager.default.removeItem(at: script) }
            let analyzer = try SongAnalyzer(executable: script.path, rate: rate, cancelled: { false }, classifier: MusicPermission())
            defer { analyzer.stop() }
            var frames = 0
            var rows: [[String: Any]] = []
            var values: [Double] = []
            for block in blocks {
                let count = try XCTUnwrap(block["frames"] as? Int)
                let time = Double(frames) / rate
                let result = try analyzer.process([Float](repeating: 0.1, count: count), startingAt: time)
                frames += count
                rows.append(["time": time, "bpm": result.reading.pulsesPerMinute as Any? ?? NSNull()])
                if let bpm = result.reading.pulsesPerMinute { values.append(bpm) }
            }
            let changes = zip(values, values.dropFirst()).filter { $0.rounded() != $1.rounded() }.count
            let octaves = zip(values, values.dropFirst()).filter { abs(log2($1 / $0)) > 0.8 }.count
            let travel = zip(values, values.dropFirst()).reduce(0.0) { $0 + abs($1.1 - $1.0) }
            let sorted = values.sorted()
            print("EVIDENCE \(file): blocks=\(blocks.count) visible=\(values.count) integerChanges=\(changes) octaveJumps=\(octaves) totalBPMMovement=\(travel) median=\(sorted.isEmpty ? 0 : sorted[sorted.count / 2])")
            if let output = env["TEMPO_TEST_EVIDENCE_OUTPUT"] {
                try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
                try JSONSerialization.data(withJSONObject: rows).write(to: URL(fileURLWithPath: output).appendingPathComponent(file))
            }
        }
    }
}

private final class MusicPermission: AudioContentClassifying {
    func process(_ samples: [Float]) throws -> AudioContentPermission { [.music] }
    func reset(rate: Double) throws {}
    func stop() {}
}
