import Foundation
import TempoCore

/// Native onset/interval detection for an explicitly selected click track.
/// The system classifier supplies a speech veto, never metronome recognition.
final class ClickTrackAnalyzer {
    private var clicks: SparseClickAnalyzer
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
            clicks = SparseClickAnalyzer(sampleRate: rate, settings: settings)
            return empty
        }
        return clicks.process(samples, startingAt: time, music: empty)
    }
}
