import Foundation

/// Conservative native pulse timing. Used only when Click track is selected in LIVE.
/// Runs on the analysis worker; never changes the samples passed to the music model.
public struct SparseClickAnalyzer {
    private var analyzer: ClickAnalyzer
    private let rate: Double
    private var activity: [(end: Double, frames: Int, active: Int)] = []
    private var lastOnset: Double?

    public init(sampleRate: Double, settings: DetectorSettings = .init()) {
        rate = sampleRate
        analyzer = ClickAnalyzer(sampleRate: sampleRate, settings: settings)
    }

    public mutating func process(_ samples: [Float], startingAt time: Double,
                                 music: AnalysisSnapshot) -> AnalysisSnapshot {
        let click = analyzer.process(samples, startingAt: time)
        let end = time + Double(samples.count) / rate
        // Require quiet space between clicks over the preceding two seconds.
        // Metronomes may have longer percussion tails than a short tick.
        // Sustained tones and dense music still cannot acquire a transient tempo.
        activity.removeAll { $0.end <= end - 2 || $0.end > time + 2 / rate }
        activity.append((end, samples.count, samples.reduce(0) { $0 + (abs($1) >= 0.01 ? 1 : 0) }))
        if let beat = click.lastBeatTime { lastOnset = beat }
        let total = activity.reduce(0) { $0 + $1.frames }
        let active = activity.reduce(0) { $0 + $1.active }
        let recent = lastOnset.map { end - $0 <= max(0.4, (click.reading.pulseMilliseconds ?? 0) / 1000 * 1.5) } ?? false
        guard music.reading.pulseMilliseconds == nil || music.reading.isStale,
              click.reading.isStable, recent, total > 0,
              Double(active) / Double(total) < 0.5 else { return music }
        return AnalysisSnapshot(reading: click.reading, peakDB: music.peakDB,
                                clipped: music.clipped, detectedOnsets: click.detectedOnsets,
                                discontinuities: click.discontinuities, lastBeatTime: click.lastBeatTime)
    }
}
