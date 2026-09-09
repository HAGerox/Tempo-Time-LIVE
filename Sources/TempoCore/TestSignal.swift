import Foundation

/// Deterministic, silent PCM source used by the app's explicitly labelled test mode.
/// Accents vary pitch and level; the detector still measures every click.
public enum TestSignal {
    public static func samples(startFrame: Int, count: Int, sampleRate: Double = 48_000,
                               pulsesPerMinute: Double = 120) -> [Float] {
        let interval = 60 / pulsesPerMinute
        return (startFrame..<startFrame + count).map { frame in
            let time = Double(frame) / sampleRate
            let beat = Int(floor(time / interval))
            let phase = time - Double(beat) * interval
            guard phase < 0.025 else { return 0 }
            let frequency = beat % 4 == 0 ? 1760.0 : 880.0
            return Float((beat % 4 == 0 ? 0.65 : 0.4) * exp(-phase * 180) * sin(2 * .pi * frequency * phase))
        }
    }
}
