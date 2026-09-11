import AVFoundation
import SoundAnalysis
import TempoCore

protocol AudioContentClassifying: AnyObject {
    func process(_ samples: [Float]) throws -> AudioContentPermission
    func reset(rate: Double) throws
    func stop()
}

/// The system classifier owns its inference work. Called only on the serial
/// analysis worker, with a bounded result mailbox shared with its observer.
final class SoundContentAnalyzer: NSObject, AudioContentClassifying, SNResultsObserving {
    private var analyzer: SNAudioStreamAnalyzer?
    private var format: AVAudioFormat!
    private var frames: AVAudioFramePosition = 0
    private var gate = AudioContentGate()
    private let lock = NSLock()
    private var pending: [AudioContentEvidence] = []
    private var failure: Error?

    init(rate: Double) throws {
        super.init()
        try reset(rate: rate)
    }

    func reset(rate: Double) throws {
        stop()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else {
            throw InputError.message("Could not prepare sound classification for this input.")
        }
        self.format = format
        frames = 0; gate.reset()
        lock.lock(); pending.removeAll(keepingCapacity: true); failure = nil; lock.unlock()
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: 1.5, preferredTimescale: 16000)
        request.overlapFactor = 2.0 / 3.0
        let analyzer = SNAudioStreamAnalyzer(format: format)
        try analyzer.add(request, withObserver: self)
        self.analyzer = analyzer
    }

    func stop() {
        // Once removal returns, the previous request cannot deliver more results.
        analyzer?.removeAllRequests(); analyzer = nil
    }

    func process(_ samples: [Float]) throws -> AudioContentPermission {
        guard let analyzer else { throw InputError.message("Sound classification stopped. Re-select the input to retry.") }
        if !samples.isEmpty {
            let count = AVAudioFrameCount(samples.count)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
                  let data = buffer.floatChannelData?[0] else {
                throw InputError.message("Could not allocate the sound analysis buffer.")
            }
            samples.withUnsafeBufferPointer { data.update(from: $0.baseAddress!, count: samples.count) }
            buffer.frameLength = count
            analyzer.analyze(buffer, atAudioFramePosition: frames)
            frames += AVAudioFramePosition(count)
        }
        lock.lock()
        let results = pending; pending.removeAll(keepingCapacity: true)
        let error = failure
        lock.unlock()
        if let error { throw InputError.message("Sound classification failed: \(error.localizedDescription). Re-select the input to retry.") }
        for result in results { gate.update(result) }
        return gate.permissions(at: Double(frames) / format.sampleRate)
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        func score(_ identifier: String) -> Double { result.classification(forIdentifier: identifier)?.confidence ?? 0 }
        // These are semantic outputs of the system model, not a catalogue of
        // instruments or DAW-specific metronome samples.
        let end = CMTimeRangeGetEnd(result.timeRange).seconds
        let evidence = AudioContentEvidence(end: end,
            music: max(score("music"), score("singing"), score("choir_singing"), score("rapping")),
            speech: score("speech"))
        lock.lock(); defer { lock.unlock() }
        if pending.count == 32 { pending.removeFirst() }
        pending.append(evidence)
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        lock.lock(); failure = error; lock.unlock()
    }
}
