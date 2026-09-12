import Foundation

/// Publication policy shared by audio detectors, never by manual taps.
/// Evidence timestamps must advance: repeated PCM replies cannot confirm a change.
public struct TempoLock {
    private var bpm: Double?
    private var lastEvidence: Double?
    private var lastSupport: Double?
    private var recent: [(time: Double, bpm: Double)] = []
    private var candidate: [(time: Double, bpm: Double)] = []
    private var candidateStart: Double?
    public init() {}
    public mutating func reset() { self = TempoLock() }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// Returns whether this observation may also steer beat phase.
    @discardableResult
    public mutating func observe(bpm value: Double, at time: Double, supportedSince: Double? = nil) -> Bool {
        guard value.isFinite, (20...600).contains(value), time.isFinite,
              lastEvidence.map({ time > $0 }) ?? true else { return false }
        if let lastEvidence, time - lastEvidence > 10 { reset() }
        let elapsed = lastEvidence.map { time - $0 } ?? 0
        lastEvidence = time
        guard let current = bpm else { bpm = value; lastSupport = time; recent = [(time, value)]; return true }
        if abs(value / current - 1) <= 0.025 {
            lastSupport = time
            candidate.removeAll(keepingCapacity: true); candidateStart = nil
            recent.removeAll { time - $0.time > 3 }
            recent.append((time, value))
            if recent.count > 128 { recent.removeFirst() }
            let target = median(recent.map(\.bpm))
            // A small dead band prevents frame quantization from moving the lock.
            if abs(target - current) > 0.4 {
                bpm = current + (target - current) * (1 - exp(-min(elapsed, 1) / 2))
            }
            return true
        }
        recent.removeAll(keepingCapacity: true)
        if let last = candidate.last, time - last.time > max(1.5, 90 / value) {
            candidate.removeAll(keepingCapacity: true); candidateStart = nil
        }
        if let first = candidate.first, abs(value / first.bpm - 1) > 0.025 {
            candidate.removeAll(keepingCapacity: true); candidateStart = nil
        }
        if candidate.isEmpty {
            // A reviewed fit can already contain several seconds of matching beats.
            // Credit that audio once; overlapping reviews never add its duration again.
            let start = supportedSince.flatMap { $0.isFinite && $0 <= time ? $0 : nil } ?? time
            candidateStart = max(time - 5, start)
        }
        candidate.append((time, value))
        if candidate.count > 256 { candidate.removeFirst() }
        let ratio = value / current
        let octave = abs(log2(ratio).magnitude - 1) < 0.08
        let confirmation = octave ? 5.0 : 3.0
        if let start = candidateStart, time - start >= confirmation, candidate.count >= (supportedSince == nil ? 4 : 3) {
            lastSupport = time
            bpm = median(candidate.map(\.bpm))
            recent = [(time, bpm!)]
            candidate.removeAll(keepingCapacity: true); candidateStart = nil
            return true
        }
        return false
    }

    public func reading(at time: Double, source: TempoReading) -> TempoReading {
        let fresh = lastEvidence.map { time - $0 <= max(3, 180 / (bpm ?? 120) + 0.08) } ?? false
        let supported = lastSupport.map { time - $0 <= 10 } ?? false
        let value = fresh && supported ? bpm : nil
        return TempoReading(pulseMilliseconds: value.map { 60_000 / $0 },
                            intervalCount: source.intervalCount, jitterMilliseconds: source.jitterMilliseconds,
                            isStable: value != nil && candidate.isEmpty && source.isStable,
                            isStale: value == nil, isChanging: !candidate.isEmpty,
                            pulseCount: source.pulseCount)
    }
}
