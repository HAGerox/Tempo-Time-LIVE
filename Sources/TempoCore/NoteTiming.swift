import Foundation

/// BPM is explicitly quarter-note BPM. A measured pulse has no inherent note value.
public enum ClickUnit: String, CaseIterable, Codable, Sendable {
    case quarter, eighth, sixteenth, dottedQuarter, half
    public var quarterNotes: Double {
        switch self {
        case .quarter: return 1
        case .eighth: return 0.5
        case .sixteenth: return 0.25
        case .dottedQuarter: return 1.5
        case .half: return 2
        }
    }
    public var label: String {
        switch self {
        case .quarter: return "Quarter · crotchet"
        case .eighth: return "Eighth · quaver"
        case .sixteenth: return "Sixteenth · semiquaver"
        case .dottedQuarter: return "Dotted quarter"
        case .half: return "Half · minim"
        }
    }
}

public enum TimingBasis: String, CaseIterable, Codable, Sendable {
    case pulse, notes
    public var label: String { self == .pulse ? "Click fractions" : "Note values" }
}

public enum NoteModifier: String, CaseIterable, Codable, Sendable {
    case straight, dotted, triplet
    public var multiplier: Double {
        switch self { case .straight: return 1; case .dotted: return 1.5; case .triplet: return 2 / 3 }
    }
    public var label: String { rawValue.capitalized }
}

public struct TimingRow: Identifiable, Equatable, Sendable {
    public let denominator: Int
    public let milliseconds: Double
    public var id: Int { denominator }
    public var fraction: String { denominator == 1 ? "1" : "1/\(denominator)" }
}

public enum NoteTiming {
    public static func quarterBPM(pulseMilliseconds: Double, clickUnit: ClickUnit) -> Double? {
        guard pulseMilliseconds.isFinite, pulseMilliseconds > 0 else { return nil }
        return 60_000 * clickUnit.quarterNotes / pulseMilliseconds
    }

    public static func rows(pulseMilliseconds: Double, basis: TimingBasis,
                            clickUnit: ClickUnit, modifier: NoteModifier) -> [TimingRow] {
        guard pulseMilliseconds.isFinite, pulseMilliseconds > 0 else { return [] }
        let base = basis == .pulse ? pulseMilliseconds : pulseMilliseconds * 4 / clickUnit.quarterNotes
        return [1, 2, 4, 8, 16, 32, 64, 128].map {
            TimingRow(denominator: $0, milliseconds: base * modifier.multiplier / Double($0))
        }
    }
}
