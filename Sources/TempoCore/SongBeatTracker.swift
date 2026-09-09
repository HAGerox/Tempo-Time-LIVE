import Foundation

/// Musical beat lock, independent of capture and presentation. Likelihood is
/// evidence for a beat, not a calibrated probability that music is playing.
public struct SongBeatTracker {
    private var candidates: [(time: Double, strength: Double)] = []
    private var period: Double?
    public private(set) var lastBeat: Double?
    public private(set) var confidence = 0.0
    private var count = 0
    public init() {}
    public mutating func reset() { self = SongBeatTracker() }

    public mutating func advance(to time: Double) {
        if let lastBeat, let period, time - lastBeat > period * 3 + 0.08 {
            self.period = nil; self.lastBeat = nil; confidence = 0; count = 0
        }
        if let last = candidates.last, time - last.time > 1.5 { candidates = [] }
    }

    /// Returns true only for evidence allowed to steer the visual beat phase.
    @discardableResult
    public mutating func addBeat(at time: Double, strength: Double) -> Bool {
        guard time.isFinite, strength.isFinite, strength >= 0.4, strength <= 1 else { return false }
        guard candidates.last.map({ time > $0.time }) ?? true,
              lastBeat.map({ time > $0 }) ?? true else { return false }
        advance(to: time)
        candidates.append((time, strength))
        if candidates.count > 5 { candidates.removeFirst() }
        if let period, let lastBeat {
            let distance = time - lastBeat
            let steps = max(1, Int((distance / period).rounded()))
            let error = distance - Double(steps) * period
            if confidence * 0.75 + strength * 0.25 >= 0.55 && steps <= 3 && abs(error) <= max(0.045, period * 0.12) {
                // A missing detection does not halve the musical tempo.
                self.period = period + (distance / Double(steps) - period) * 0.2
                self.lastBeat = time
                confidence = confidence * 0.75 + strength * 0.25
                count += 1
                return true
            }
        }
        // Fit five consecutive beats before starting or changing the lock.
        // Frame quantization is tolerated without trusting isolated transients.
        guard candidates.count == 5 else { return false }
        let meanTime = candidates.map(\.time).reduce(0, +) / 5
        let slope = candidates.enumerated().reduce(0.0) { $0 + (Double($1.offset) - 2) * ($1.element.time - meanTime) } / 10
        guard slope >= 60 / 215.0, slope <= 60 / 55.0 else { return false }
        let residual = candidates.enumerated().map { abs($0.element.time - (meanTime + (Double($0.offset) - 2) * slope)) }.max() ?? .infinity
        let evidence = candidates.map(\.strength).reduce(0, +) / 5
        guard residual <= max(0.03, slope * 0.08), evidence >= 0.55 else { return false }
        period = slope; lastBeat = time; confidence = evidence; count = 5
        return true
    }

    public func reading(at time: Double) -> TempoReading {
        let age = lastBeat.map { max(0, time - $0) } ?? .infinity
        let valid = period.map { age <= $0 * 3 + 0.08 } ?? false
        return TempoReading(pulseMilliseconds: valid ? period.map { $0 * 1000 } : nil,
                            intervalCount: max(0, count - 1), jitterMilliseconds: 0,
                            isStable: valid && age <= (period ?? 0) * 1.5,
                            isStale: !valid, isChanging: false, pulseCount: count)
    }

    public func status(at time: Double, silent: Bool) -> String {
        if silent { return "No signal" }
        let value = reading(at: time)
        if value.pulseMilliseconds == nil { return "Listening" }
        return value.isStable ? "Tracking" : "Following"
    }
}
