import Foundation
import TempoCore

struct Report: Encodable {
    let pulseMilliseconds: Double?
    let pulsesPerMinute: Double?
    let quarterNoteBPM: Double?
    let stable: Bool
    let stale: Bool
    let jitterMilliseconds: Double
    let detectedClicks: Int
    let sampleRate: Double
    let channel: Int
    let clickUnit: ClickUnit
    let noteMilliseconds: [String: Double]
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.isEmpty || args.contains("--help") {
        print("Usage: tempo-analyze FILE.wav [--channel 1] [--threshold -30] [--retrigger 80] [--click-unit quarter]\n       tempo-analyze --demo\nChannels are 1-based. Click units: quarter, eighth, sixteenth, dottedQuarter, half.\nOutputs JSON. --demo analyzes eight seconds of generated PCM, without playing audio.")
        exit(0)
    }
    var channel = 1, threshold = -30.0, retrigger = 80.0
    var unit = ClickUnit.quarter
    var cursor = 1
    while cursor < args.count {
        guard cursor + 1 < args.count else { throw WaveError.invalid("Missing value for \(args[cursor]).") }
        let value = args[cursor + 1]
        switch args[cursor] {
        case "--channel": guard let n = Int(value), n > 0 else { throw WaveError.invalid("Channel must be a positive integer.") }; channel = n
        case "--threshold": guard let n = Double(value), n.isFinite, (-60 ... -3).contains(n) else { throw WaveError.invalid("Threshold must be -60…-3 dBFS.") }; threshold = n
        case "--retrigger": guard let n = Double(value), n.isFinite, (40...250).contains(n) else { throw WaveError.invalid("Retrigger must be 40…250 ms.") }; retrigger = n
        case "--click-unit": guard let n = ClickUnit(rawValue: value) else { throw WaveError.invalid("Unknown click unit.") }; unit = n
        default: throw WaveError.invalid("Unknown option: \(args[cursor]).")
        }
        cursor += 2
    }
    let demo = args[0] == "--demo"
    let wave = try demo ? nil : WaveFile(data: Data(contentsOf: URL(fileURLWithPath: args[0]), options: .mappedIfSafe))
    guard channel <= (wave?.channels ?? 1) else { throw WaveError.invalid("Selected channel is unavailable.") }
    let rate = wave?.sampleRate ?? 48_000
    let frames = wave?.frameCount ?? 384_000
    var analyzer = ClickAnalyzer(sampleRate: rate, settings: .init(thresholdDB: threshold, retriggerMilliseconds: retrigger))
    var snapshot = analyzer.process([], startingAt: 0)
    var onsets = 0
    for start in stride(from: 0, to: frames, by: 1024) {
        let end = min(frames, start + 1024)
        let pcm = try wave?.samples(channel: channel - 1, frames: start..<end)
            ?? TestSignal.samples(startFrame: start, count: end - start)
        snapshot = analyzer.process(pcm, startingAt: Double(start) / rate)
        onsets += snapshot.detectedOnsets
    }
    let pulse = snapshot.reading.pulseMilliseconds
    let rows = NoteTiming.rows(pulseMilliseconds: pulse ?? 0, basis: .notes, clickUnit: unit, modifier: .straight)
    let report = Report(pulseMilliseconds: pulse, pulsesPerMinute: snapshot.reading.pulsesPerMinute,
                        quarterNoteBPM: pulse.flatMap { NoteTiming.quarterBPM(pulseMilliseconds: $0, clickUnit: unit) },
                        stable: snapshot.reading.isStable, stale: snapshot.reading.isStale,
                        jitterMilliseconds: snapshot.reading.jitterMilliseconds, detectedClicks: onsets,
                        sampleRate: rate, channel: channel, clickUnit: unit,
                        noteMilliseconds: Dictionary(uniqueKeysWithValues: rows.map { ($0.fraction, $0.milliseconds) }))
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(report), as: UTF8.self))
} catch {
    FileHandle.standardError.write(Data("tempo-analyze: \(error.localizedDescription)\n".utf8))
    exit(1)
}
