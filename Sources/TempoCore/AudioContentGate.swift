import Foundation

/// Classification evidence controls which tempo analyses may publish a reading.
/// Scores are model evidence, not calibrated probabilities of an audio category.
public struct AudioContentEvidence: Sendable {
    public let end: Double
    public let music: Double
    public let speech: Double
    public init(end: Double, music: Double, speech: Double) {
        self.end = end; self.music = music; self.speech = speech
    }
}

public struct AudioContentPermission: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let music = Self(rawValue: 1)
    public static let speechClear = Self(rawValue: 2)
}

public struct AudioContentGate {
    private var latest: Double?
    private var musicWindows = 0
    private var safeContextWindows = 0
    private var musicMisses = 0
    private var permission: AudioContentPermission = []
    public init() {}

    public mutating func reset() { self = Self() }

    public mutating func update(_ evidence: AudioContentEvidence) {
        guard evidence.end.isFinite, evidence.end >= 0,
              [evidence.music, evidence.speech].allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              latest.map({ evidence.end > $0 }) ?? true else { return }
        if let latest, evidence.end - latest > 1.5 { reset() }
        latest = evidence.end

        // Two overlapping windows establish music. A lower continuation threshold
        // tolerates quiet passages and vocals without repeatedly losing the lock.
        if evidence.music >= 0.5 {
            musicWindows += 1; musicMisses = 0
            if musicWindows >= 2 { permission.insert(.music) }
        } else {
            musicWindows = 0
            if evidence.music >= 0.35 && permission.contains(.music) {
                musicMisses = 0
            } else {
                musicMisses += 1
                if evidence.speech >= 0.6 || musicMisses >= 2 { permission.remove(.music) }
            }
        }

        // Absence of speech is only a veto check, never positive click evidence.
        if evidence.speech < 0.2 {
            safeContextWindows = min(2, safeContextWindows + 1)
        } else {
            safeContextWindows = 0
        }
    }

    public mutating func permissions(at time: Double) -> AudioContentPermission {
        guard let latest, time.isFinite, time >= latest, time - latest <= 1.5 else {
            reset(); return []
        }
        var result = permission
        // This is only a speech veto for explicitly selected Click track mode.
        // It never classifies the source as a metronome or supplies a tempo.
        if safeContextWindows >= 2 { result.insert(.speechClear) }
        return result
    }
}
