import Foundation
import TempoCore

/// Native onset/interval detection for an explicitly selected click track.
/// The system classifier supplies a speech veto, never metronome recognition.
final class ClickTrackAnalyzer {
    private var clicks: SparseClickAnalyzer
    private var tempoLock = TempoLock()
    private let classifier: AudioContentClassifying
    private let rate: Double
    private let settings: DetectorSettings
    private var expectedTime: Double?

    init(rate: Double, settings: DetectorSettings = .init(),
         classifier: AudioContentClassifying? = nil) throws {
        self.rate = rate; self.settings = settings
        clicks = SparseClickAnalyzer(sampleRate: rate, settings: settings)
        self.classifier = try classifier ?? SoundContentAnalyzer(rate: rate)
    }

    func stop() { classifier.stop() }

    func process(_ samples: [Float], startingAt time: Double) throws -> AnalysisSnapshot {
        if let expectedTime, abs(time - expectedTime) > 2 / rate {
            try classifier.reset(rate: rate)
            tempoLock.reset()
            clicks = SparseClickAnalyzer(sampleRate: rate, settings: settings)
        }
        expectedTime = time + Double(samples.count) / rate
        let permission = try classifier.process(samples)
        let peak = samples.reduce(0.0) { max($0, $1.isFinite ? abs(Double($1)) : 0) }
        let empty = AnalysisSnapshot(
            reading: TempoTracker().reading(at: time),
            peakDB: max(-120, 20 * log10(max(peak, 0.000001))),
            clipped: peak >= 1, detectedOnsets: 0, discontinuities: 0)
        guard permission.contains(.speechClear) else {
            tempoLock.reset()
            clicks = SparseClickAnalyzer(sampleRate: rate, settings: settings)
            return empty
        }
        let result = clicks.process(samples, startingAt: time, music: empty)
        var beat = result.lastBeatTime
        var onsets = result.detectedOnsets
        if let evidence = beat, let bpm = result.reading.pulsesPerMinute {
            if !tempoLock.observe(bpm: bpm, at: evidence) { beat = nil; onsets = 0 }
        }
        let reading = tempoLock.reading(at: time + Double(samples.count) / rate, source: result.reading)
        return AnalysisSnapshot(reading: reading, peakDB: result.peakDB, clipped: result.clipped,
                                detectedOnsets: reading.isStale ? 0 : onsets,
                                discontinuities: result.discontinuities,
                                lastBeatTime: reading.isStale ? nil : beat)
    }
}
