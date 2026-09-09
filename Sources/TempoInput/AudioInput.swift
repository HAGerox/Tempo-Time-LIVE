import Foundation
import AudioBridge
import TempoCore

public struct InputDevice: Identifiable, Equatable {
    public let id: UInt32
    public let uid: String
    public let name: String
    public let channels: Int
    public let sampleRate: Double
    public init(id: UInt32, uid: String, name: String, channels: Int, sampleRate: Double) {
        self.id = id; self.uid = uid; self.name = name
        self.channels = channels; self.sampleRate = sampleRate
    }
}

public enum InputUpdate {
    case started(Double)
    case measurement(AnalysisSnapshot, peak: Double, clipped: Bool, onsets: Int)
    case failed(String)
}

/// All capture ownership and analysis are confined to this serial worker.
/// The C callback only renders into preallocated memory and writes the SPSC queue.
public final class AudioInput {
    private let queue = DispatchQueue(label: "io.github.hagerox.tempotime.live.analysis", qos: .userInitiated)
    private var capture: OpaquePointer?
    private var timer: DispatchSourceTimer?
    private var analyzer: ClickAnalyzer?
    private var song: SongAnalyzer?
    private var buffer = [Float](repeating: 0, count: Int(TT_BLOCK_FRAMES))
    private var lastData = ProcessInfo.processInfo.systemUptime
    private var testFrame = 0
    private let cancellationLock = NSLock()
    private var requestID = 0
    private func invalidate() -> Int {
        cancellationLock.lock(); defer { cancellationLock.unlock() }
        requestID += 1; return requestID
    }
    private func cancelled(_ token: Int) -> Bool {
        cancellationLock.lock(); defer { cancellationLock.unlock() }
        return token != requestID
    }
    public init() {}

    public func devices(completion: @escaping (Result<[InputDevice], Error>) -> Void) {
        queue.async {
            let count = tt_list_devices(nil, 0)
            guard count >= 0 else {
                completion(.failure(InputError.message("Could not list audio inputs (Core Audio \(count)). Check that an input device is connected.")))
                return
            }
            var raw = [TTDeviceInfo](repeating: TTDeviceInfo(), count: max(Int(count), 1))
            let capacity = Int32(raw.count)
            let actual = tt_list_devices(&raw, capacity)
            guard actual >= 0 else {
                completion(.failure(InputError.message("Could not refresh audio inputs (Core Audio \(actual)).")))
                return
            }
            let devices = raw.prefix(min(Int(actual), raw.count)).map { value -> InputDevice in
                var value = value
                let name = withUnsafePointer(to: &value.name) { pointer in
                    pointer.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
                }
                let uid = withUnsafePointer(to: &value.uid) { pointer in
                    pointer.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
                }
                return InputDevice(id: value.id, uid: uid, name: name, channels: Int(value.channels), sampleRate: value.sample_rate)
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            completion(.success(devices))
        }
    }

    public func start(device: InputDevice?, channel: Int, settings: DetectorSettings,
               receive: @escaping (InputUpdate) -> Void) {
        let token = invalidate()
        queue.async {
            self.stopOnQueue(preserveModel: true)
            guard !self.cancelled(token) else { return }
            guard channel > 0, channel <= (device?.channels ?? 1) else {
                receive(.failed("Choose an available input channel."))
                return
            }
            // Load the model before opening capture, so startup cannot overflow PCM.
            if device != nil, let executable = ProcessInfo.processInfo.environment["TEMPO_BEATNET_WORKER"] {
                do {
                    if let song = self.song {
                        try song.reset(rate: device!.sampleRate, cancelled: { self.cancelled(token) })
                    } else {
                        self.song = try SongAnalyzer(executable: executable, rate: device!.sampleRate, cancelled: { self.cancelled(token) })
                    }
                }
                catch { self.stopOnQueue(); receive(.failed(error.localizedDescription)); return }
            }
            guard !self.cancelled(token) else { return }
            let rate: Double
            if let device = device {
                var error: Int32 = 0
                guard let capture = tt_capture_start(device.id, UInt32(channel - 1), &error) else {
                    self.stopOnQueue()
                    receive(.failed("Could not open \(device.name), channel \(channel) (Core Audio \(error)). Check the device is running and audio input permission is enabled."))
                    return
                }
                self.capture = capture
                rate = tt_capture_sample_rate(capture)
                if self.song != nil && abs(rate - device.sampleRate) > 1 {
                    self.stopOnQueue()
                    receive(.failed("Input sample rate changed. Reconnecting BeatNet.")); return
                }
            } else { rate = 48_000 }
            self.analyzer = ClickAnalyzer(sampleRate: rate, settings: settings)
            self.lastData = ProcessInfo.processInfo.systemUptime
            self.testFrame = 0
            receive(.started(rate))
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(33))
            timer.setEventHandler { [weak self] in
                guard let self = self, !self.cancelled(token) else { return }
                self.poll(test: device == nil, receive: receive)
            }
            self.timer = timer
            timer.resume()
        }
    }

    public func stop(preserveModel: Bool = false, completion: (() -> Void)? = nil) {
        _ = invalidate()
        queue.async { self.stopOnQueue(preserveModel: preserveModel); completion?() }
    }

    private func stopOnQueue(preserveModel: Bool = false) {
        timer?.cancel(); timer = nil
        if let capture = capture { tt_capture_stop(capture) }
        capture = nil; analyzer = nil
        if !preserveModel { song?.stop(); song = nil }
    }

    private func poll(test: Bool, receive: (InputUpdate) -> Void) {
        if test {
            let samples = TestSignal.samples(startFrame: testFrame, count: 1584)
            let result = analyzer!.process(samples, startingAt: Double(testFrame) / 48_000)
            testFrame += samples.count
            receive(.measurement(result, peak: result.peakDB, clipped: result.clipped, onsets: result.detectedOnsets))
            return
        }
        guard let capture = capture else { return }
        if tt_capture_error(capture) != 0 || tt_capture_dropped(capture) != 0 {
            let detail = tt_capture_dropped(capture) > 0 ? "The audio analysis queue overflowed." : "The audio device reported error \(tt_capture_error(capture))."
            stopOnQueue()
            receive(.failed("\(detail) Check the input; Tempo Time LIVE will reconnect automatically."))
            return
        }
        var songSamples: [Float] = []
        var songStart = 0.0
        var latest: AnalysisSnapshot?
        var peak = -120.0, clipped = false, onsets = 0
        for _ in 0..<Int(TT_QUEUE_BLOCKS) {
            var time = 0.0
            let capacity = UInt32(buffer.count)
            let count = tt_capture_read(capture, &buffer, capacity, &time)
            if count == 0 { break }
            if song != nil {
                if songSamples.isEmpty { songStart = time }
                songSamples.append(contentsOf: buffer.prefix(Int(count)))
                if songSamples.count >= 8192 { break }
                continue
            }
            let snapshot = buffer.withUnsafeBufferPointer {
                analyzer!.process(UnsafeBufferPointer(start: $0.baseAddress, count: Int(count)), startingAt: time)
            }
            latest = snapshot
            peak = max(peak, snapshot.peakDB); clipped = clipped || snapshot.clipped
            onsets += snapshot.detectedOnsets
        }
        if !songSamples.isEmpty, let song = song {
            do {
                let result = try song.process(songSamples, startingAt: songStart)
                latest = result; peak = result.peakDB; clipped = result.clipped; onsets = result.detectedOnsets
            } catch {
                stopOnQueue(); receive(.failed(error.localizedDescription)); return
            }
        }
        if let latest = latest {
            lastData = ProcessInfo.processInfo.systemUptime
            receive(.measurement(latest, peak: peak, clipped: clipped, onsets: onsets))
        } else if ProcessInfo.processInfo.systemUptime - lastData > 2 {
            stopOnQueue()
            receive(.failed("The device stopped delivering audio. Check Dante Virtual Soundcard or reconnect your interface, Tempo Time LIVE will reconnect automatically."))
        }
    }
}

enum InputError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}
