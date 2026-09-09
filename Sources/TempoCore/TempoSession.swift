import Foundation

/// Manual taps temporarily override the latest audio reading without stopping capture.
public struct TempoSession {
    public static let manualTimeout = 30.0
    private var taps = TempoTracker()
    private var lastTap: Double?
    private var manualReading: TempoReading?
    public var audioReading: TempoReading?

    public init() {}

    public mutating func tap(at time: Double) {
        guard time.isFinite, lastTap.map({ time > $0 }) ?? true else { return }
        if let previous = lastTap, time - previous >= Self.manualTimeout { taps.reset() }
        taps.addOnset(at: time)
        lastTap = time
        manualReading = taps.reading(at: time)
    }

    public func isManual(at time: Double) -> Bool {
        guard let lastTap else { return false }
        return time - lastTap < Self.manualTimeout
    }

    public func reading(at time: Double) -> TempoReading? {
        isManual(at: time) ? manualReading : audioReading
    }
}
