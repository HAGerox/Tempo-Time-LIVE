import Foundation

public struct DetectorSettings: Equatable, Codable, Sendable {
    public var thresholdDB: Double
    public var retriggerMilliseconds: Double
    public init(thresholdDB: Double = -30, retriggerMilliseconds: Double = 80) {
        self.thresholdDB = thresholdDB.isFinite ? min(-3, max(-60, thresholdDB)) : -30
        self.retriggerMilliseconds = retriggerMilliseconds.isFinite ? min(250, max(40, retriggerMilliseconds)) : 80
    }
}

/// A DC-blocked peak envelope, Schmitt trigger and minimum onset spacing.
/// Consume on a worker, using audio sample timestamps rather than UI arrival times.
public struct ClickDetector: Sendable {
    public let sampleRate: Double
    public let settings: DetectorSettings
    private let threshold: Double
    private let release: Double
    private let dcCoefficient: Double
    private var previousInput = 0.0
    private var previousFiltered = 0.0
    private var envelope = 0.0
    private var quietSamples = 0
    private var armed = true
    private var lastOnset = -Double.infinity

    public init(sampleRate: Double, settings: DetectorSettings = .init()) {
        precondition(sampleRate.isFinite && sampleRate >= 8_000 && sampleRate <= 384_000)
        self.sampleRate = sampleRate
        self.settings = DetectorSettings(thresholdDB: settings.thresholdDB,
                                         retriggerMilliseconds: settings.retriggerMilliseconds)
        threshold = pow(10, self.settings.thresholdDB / 20)
        release = exp(-1 / (sampleRate * 0.003))
        dcCoefficient = exp(-2 * .pi * 20 / sampleRate)
    }

    public mutating func process(sample: Float, at time: Double) -> Bool {
        guard time.isFinite else { return false }
        let input = sample.isFinite ? Double(sample) : 0
        let filtered = input - previousInput + dcCoefficient * previousFiltered
        previousInput = input
        previousFiltered = filtered
        envelope = max(abs(filtered), envelope * release)
        if envelope < threshold * 0.5 {
            quietSamples += 1
            if quietSamples >= Int(sampleRate * 0.004) { armed = true }
        } else { quietSamples = 0 }
        if armed && envelope >= threshold {
            // Consume crossings inside the guard too. Otherwise a rejected echo can
            // become a delayed false onset when the guard expires during its tail.
            armed = false
            if time - lastOnset >= settings.retriggerMilliseconds / 1_000 {
                lastOnset = time
                return true
            }
        }
        return false
    }
}

public struct AnalysisSnapshot: Sendable {
    public let reading: TempoReading
    public let peakDB: Double
    public let clipped: Bool
    public let detectedOnsets: Int
    public let discontinuities: Int
    public let songStatus: String?
    public let lastBeatTime: Double?
    public init(reading: TempoReading, peakDB: Double, clipped: Bool, detectedOnsets: Int, discontinuities: Int, lastBeatTime: Double? = nil, songStatus: String? = nil) {
        self.reading = reading; self.peakDB = peakDB; self.clipped = clipped
        self.detectedOnsets = detectedOnsets; self.discontinuities = discontinuities
        self.songStatus = songStatus
        self.lastBeatTime = lastBeatTime
    }
}

public struct ClickAnalyzer: Sendable {
    private var detector: ClickDetector
    private var tracker = TempoTracker()
    private var expectedTime: Double?
    private var discontinuities = 0
    public init(sampleRate: Double, settings: DetectorSettings = .init()) {
        detector = ClickDetector(sampleRate: sampleRate, settings: settings)
    }

    public mutating func process(_ samples: UnsafeBufferPointer<Float>, startingAt time: Double) -> AnalysisSnapshot {
        if let expected = expectedTime, abs(time - expected) > 2 / detector.sampleRate {
            detector = ClickDetector(sampleRate: detector.sampleRate, settings: detector.settings)
            tracker.reset()
            discontinuities += 1
        }
        var peak: Float = 0
        var count = 0
        var lastBeatTime: Double?
        for (index, sample) in samples.enumerated() {
            if sample.isFinite { peak = max(peak, abs(sample)) }
            let timestamp = time + Double(index) / detector.sampleRate
            if detector.process(sample: sample, at: timestamp) {
                tracker.addOnset(at: timestamp)
                count += 1
                lastBeatTime = timestamp
            }
        }
        let endTime = time + Double(samples.count) / detector.sampleRate
        expectedTime = endTime
        return AnalysisSnapshot(reading: tracker.reading(at: endTime),
                                peakDB: max(-120, 20 * log10(max(Double(peak), 0.000001))),
                                clipped: peak >= 1, detectedOnsets: count, discontinuities: discontinuities, lastBeatTime: lastBeatTime)
    }

    public mutating func process(_ samples: [Float], startingAt time: Double) -> AnalysisSnapshot {
        samples.withUnsafeBufferPointer { process($0, startingAt: time) }
    }
}
