import Foundation

public struct TempoReading: Equatable, Sendable {
    public let pulseMilliseconds: Double?
    public let intervalCount: Int
    public let jitterMilliseconds: Double
    public let isStable: Bool
    public let isStale: Bool
    public let isChanging: Bool
    public let pulseCount: Int
    public init(pulseMilliseconds: Double?, intervalCount: Int, jitterMilliseconds: Double,
                isStable: Bool, isStale: Bool, isChanging: Bool, pulseCount: Int) {
        self.pulseMilliseconds = pulseMilliseconds
        self.intervalCount = intervalCount
        self.jitterMilliseconds = jitterMilliseconds
        self.isStable = isStable
        self.isStale = isStale
        self.isChanging = isChanging
        self.pulseCount = pulseCount
    }
    public var pulsesPerMinute: Double? { pulseMilliseconds.map { 60_000 / $0 } }
}

/// Robust intervals, with a separate candidate window for actual tempo changes.
/// Never folds intervals into an assumed musical BPM range (half/double ambiguity is real).
public struct TempoTracker: Sendable {
    private var intervals: [Double] = []
    private var candidates: [Double] = []
    private var lastOnset: Double?
    private var pulseCount = 0
    public static let minimumInterval = 0.1  // 600 clicks/minute
    public static let maximumInterval = 3.0  // 20 clicks/minute
    public init() {}

    public mutating func reset() { self = TempoTracker() }

    public mutating func addOnset(at time: Double) {
        guard time.isFinite else { return }
        guard let previous = lastOnset else { lastOnset = time; pulseCount = 1; return }
        let interval = time - previous
        guard interval > 0 else { return }
        // Do not move the anchor for a bounce, so the following real interval is intact.
        guard interval >= Self.minimumInterval - 1e-8 else { return }
        if interval > Self.maximumInterval + 1e-8 || interval > max(2.5, (estimate ?? 1) * 3) + 1e-8 {
            reset(); lastOnset = time; pulseCount = 1; return
        }
        lastOnset = time
        pulseCount += 1
        if let estimate = estimate, abs(interval - estimate) / estimate > 0.12 {
            if let candidate = candidates.last, abs(interval - candidate) / candidate < 0.08 {
                candidates.append(interval)
            } else { candidates = [interval] }
            // Three matching intervals distinguish sustained changes from a dropped click
            // or an extra transient splitting one interval in two.
            if candidates.count >= 3 {
                intervals = candidates
                candidates.removeAll(keepingCapacity: true)
            }
            return
        }
        candidates.removeAll(keepingCapacity: true)
        intervals.append(interval)
        if intervals.count > 8 { intervals.removeFirst() }
    }

    private var estimate: Double? {
        guard !intervals.isEmpty else { return nil }
        let ordered = intervals.sorted()
        let middle = ordered.count / 2
        let median = ordered.count % 2 == 0 ? (ordered[middle - 1] + ordered[middle]) / 2 : ordered[middle]
        let accepted = intervals.filter { abs($0 - median) / median <= 0.08 }
        return accepted.reduce(0, +) / Double(accepted.count)
    }

    public func reading(at time: Double) -> TempoReading {
        let value = estimate
        let jitter = value.map { mean in
            sqrt(intervals.reduce(0) { $0 + pow($1 - mean, 2) } / Double(intervals.count))
        } ?? 0
        let timeout = max(2.5, (value ?? 1) * 3)
        let stale = lastOnset.map { time - $0 > timeout } ?? false
        return TempoReading(pulseMilliseconds: value.map { $0 * 1_000 },
                            intervalCount: intervals.count, jitterMilliseconds: jitter * 1_000,
                            isStable: intervals.count >= 4 && jitter / (value ?? 1) < 0.025 && candidates.isEmpty && !stale,
                            isStale: stale, isChanging: !candidates.isEmpty, pulseCount: pulseCount)
    }
}
