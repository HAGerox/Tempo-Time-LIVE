import Foundation
import Darwin
import TempoCore

/// Worker-owned, bounded request/reply bridge. Never called by the audio callback.
final class SongAnalyzer {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var tracker = SongBeatTracker()
    private var frameOffsetSeconds = 529.0 / 22050.0
    private var supportsReview = false
    private var lastReviewID: Double?
    private var wasReviewing = false
    private var frames = 0
    private var rate: Double
    private var cancelled: () -> Bool
    private let classifier: AudioContentClassifying
    private var permission: AudioContentPermission = []
    private var musicValidFrom = 0.0
    private var expectedTime: Double?

    init(executable: String, rate: Double, cancelled: @escaping () -> Bool,
         classifier: AudioContentClassifying? = nil) throws {
        self.rate = rate
        self.cancelled = cancelled
        self.classifier = try classifier ?? SoundContentAnalyzer(rate: rate)
        process.executableURL = URL(fileURLWithPath: executable)
        // PyTorch's thread limit does not control NumPy/SciPy's OpenBLAS pool.
        // Set these before the child loads any native numerical libraries.
        var environment = ProcessInfo.processInfo.environment
        for key in ["OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS",
                    "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS", "BLIS_NUM_THREADS"] {
            environment[key] = "1"
        }
        environment["OMP_WAIT_POLICY"] = "PASSIVE"
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        do { try process.run() }
        catch {
            self.classifier.stop()
            throw InputError.message("Music analysis could not start. Reopen Tempo Time LIVE; if this continues, reinstall the app.")
        }
        let fd = input.fileHandleForWriting.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        _ = fcntl(fd, F_SETNOSIGPIPE, 1)
        do {
            try acceptHandshake(request(["rate": rate], timeout: 60))
        }
        catch { stop(); throw error }
    }

    /// Reset stream state while retaining the loaded runtime and model weights.
    func reset(rate: Double, cancelled: @escaping () -> Bool) throws {
        self.cancelled = cancelled
        try classifier.reset(rate: rate)
        try acceptHandshake(request(["rate": rate]))
        self.rate = rate
        frames = 0
        expectedTime = nil; permission = []; musicValidFrom = 0
        tracker.reset()
    }

    private func acceptHandshake(_ response: [String: Any]) throws {
        guard response["ready"] as? Bool == true else {
            throw InputError.message("BeatNet did not initialize correctly.")
        }
        // Older original-model workers omit this field (529 samples at 22.05 kHz).
        let offset = response["frameOffsetSeconds"] as? Double ?? 529.0 / 22050.0
        guard offset.isFinite, offset >= 0, offset <= 0.2,
              response["frameOffsetSeconds"] == nil || response["frameOffsetSeconds"] is Double else {
            throw InputError.message("Invalid BeatNet feature timing.")
        }
        frameOffsetSeconds = offset
        supportsReview = response["backgroundReview"] as? Bool ?? false
        lastReviewID = nil
        wasReviewing = false
    }

    func stop() {
        classifier.stop()
        try? input.fileHandleForWriting.close()
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        try? output.fileHandleForReading.close()
    }

    private func request(_ value: [String: Any], timeout: Double = 2, interruptible: Bool = true) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: value) + Data([10])
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var written = 0
        while written < data.count {
            guard (!interruptible || !cancelled()), ProcessInfo.processInfo.systemUptime < deadline else {
                throw InputError.message("BeatNet request cancelled or timed out.")
            }
            let count = data.withUnsafeBytes { bytes in
                Darwin.write(input.fileHandleForWriting.fileDescriptor, bytes.baseAddress!.advanced(by: written), data.count - written)
            }
            if count > 0 { written += count }
            else if errno == EAGAIN || errno == EINTR {
                var descriptor = pollfd(fd: input.fileHandleForWriting.fileDescriptor, events: Int16(POLLOUT), revents: 0)
                _ = Darwin.poll(&descriptor, 1, 50)
            } else { throw InputError.message("BeatNet worker disconnected.") }
        }
        var reply = Data()
        while reply.count < 65536 {
            if interruptible && cancelled() { throw InputError.message("BeatNet connection cancelled.") }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw InputError.message("BeatNet stopped responding.") }
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let status = Darwin.poll(&descriptor, 1, Int32(min(remaining, 0.1) * 1000))
            if status == 0 { continue }
            guard status > 0, let byte = try output.fileHandleForReading.read(upToCount: 1), !byte.isEmpty else {
                throw InputError.message("BeatNet stopped responding. Re-select the input to retry.")
            }
            if byte[0] == 10 {
                guard let result = try JSONSerialization.jsonObject(with: reply) as? [String: Any] else {
                    throw InputError.message("Invalid BeatNet response.")
                }
                if let error = result["error"] as? String { throw InputError.message("BeatNet: \(error)") }
                return result
            }
            reply.append(byte)
        }
        throw InputError.message("BeatNet response exceeded its limit.")
    }

    func process(_ samples: [Float], startingAt time: Double) throws -> AnalysisSnapshot {
        if let expectedTime, abs(time - expectedTime) > 2 / rate {
            try reset(rate: rate, cancelled: cancelled)
        }
        expectedTime = time + Double(samples.count) / rate
        let nextPermission = try classifier.process(samples)
        if !nextPermission.contains(.music) || !permission.contains(.music) {
            tracker.reset(); lastReviewID = nil; wasReviewing = false
            // Discard beat evidence from speech or a previously allowed passage.
            musicValidFrom = frames == 0 ? -.infinity : Double(frames) / rate
        }
        permission = nextPermission
        let encoded = samples.withUnsafeBytes { Data($0).base64EncodedString() }
        // Finish the bounded PCM reply on selection changes so the warm worker
        // protocol stays aligned. The service discards the old generation.
        let response = try request(["pcm": encoded], interruptible: false)
        guard let beats = response["beats"] as? [Double], beats.allSatisfy({ $0.isFinite && $0 >= 0 }),
              let strengths = response["strengths"] as? [Double], strengths.count == beats.count,
              strengths.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }),
              let silent = response["silent"] as? Bool,
              let reset = response["reset"] as? Bool else {
            throw InputError.message("Invalid BeatNet beat data.")
        }
        if reset || silent {
            tracker.reset()
            lastReviewID = nil
            wasReviewing = false
        }
        var accepted: [Double] = []
        if !silent && permission.contains(.music) {
            for (beat, strength) in zip(beats, strengths) {
                guard beat - frameOffsetSeconds >= musicValidFrom else { continue }
                if tracker.addBeat(at: beat, strength: strength) { accepted.append(beat) }
            }
        }
        // BeatNet emits positions in the resampled stream, not wall-clock arrival times.
        // The worker reports the feature-window offset for its selected model:
        // original BeatNet uses 529 samples, BeatNet+ uses 882 (40 ms).
        let streamOrigin = time - Double(frames) / rate
        var beatTime = accepted.last.map { streamOrigin + $0 - frameOffsetSeconds }
        frames += samples.count
        let streamTime = Double(frames) / rate
        tracker.advance(to: streamTime)
        var reading = tracker.reading(at: streamTime)
        var detectedOnsets = accepted.count
        var reviewing = false
        if supportsReview, !silent, !reset, let review = response["review"] as? [String: Any] {
            guard let period = review["period"] as? Double, period.isFinite,
                  period >= 60 / 215.0, period <= 60 / 55.0,
                  let beat = review["beat"] as? Double, beat.isFinite, beat >= 0, beat <= streamTime,
                  let quality = review["quality"] as? Double, quality.isFinite, quality >= 0.55, quality <= 1,
                  let id = review["id"] as? Double, id.isFinite, id >= 0, id <= streamTime else {
                throw InputError.message("Invalid background beat review.")
            }
            if permission.contains(.music), beat >= musicValidFrom, id >= musicValidFrom,
               streamTime - beat <= period * 3 + 0.08 {
                reviewing = true
                let fresh = !wasReviewing || lastReviewID != id
                reading = TempoReading(pulseMilliseconds: period * 1000, intervalCount: 4,
                    jitterMilliseconds: 0, isStable: streamTime - beat <= period * 1.5,
                    isStale: false, isChanging: false, pulseCount: 5)
                // Review anchors already use corrected audio time, not PF feature time.
                beatTime = fresh ? streamOrigin + beat : nil
                detectedOnsets = fresh ? 1 : 0
                lastReviewID = id
            }
        } else if supportsReview, let value = response["review"], !(value is NSNull), !(value is [String: Any]) {
            throw InputError.message("Invalid background beat review.")
        }
        if wasReviewing && !reviewing, reading.pulseMilliseconds != nil,
           let last = tracker.lastBeat {
            beatTime = streamOrigin + last - frameOffsetSeconds
            detectedOnsets = max(1, detectedOnsets)
        }
        wasReviewing = reviewing
        let peak = samples.reduce(0.0) { max($0, abs(Double($1))) }
        let musical = AnalysisSnapshot(reading: reading,
                                peakDB: max(-120, 20 * log10(max(peak, 0.000001))),
                                clipped: peak >= 1, detectedOnsets: detectedOnsets, discontinuities: 0, lastBeatTime: beatTime,
                                songStatus: tracker.status(at: streamTime, silent: silent))
        return musical
    }
}
