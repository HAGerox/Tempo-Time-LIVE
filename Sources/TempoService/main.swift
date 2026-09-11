import Foundation
import AVFoundation
import TempoCore
import TempoInput

struct Command: Decodable {
    let action: String
    var uid: String?
    var channel: Int?
    var mode: DetectionMode?
}

final class Service {
    let queue = DispatchQueue(label: "tempo.service")
    let input = AudioInput()
    // The enclosing LIVE bundle supplies this app's independent preferences domain.
    let defaults = UserDefaults.standard
    var session = TempoSession()
    var devices: [InputDevice] = []
    var uid: String
    var channel: Int
    var mode: DetectionMode
    var listening = false
    var starting = false
    var peakDB = -120.0
    var peakTime = 0.0
    var clippedTime = -Double.infinity
    var error: String?
    var generation = 0
    var ticks = 0
    var songStatus: String?
    var beatSequence = 0
    var lastBeatTime = 0.0
    var timer: DispatchSourceTimer?
    var lastJSON = Data()
    let demo: Bool
    var device: InputDevice? { devices.first { $0.uid == uid } }
    var now: Double { ProcessInfo.processInfo.systemUptime }

    init() {
        demo = CommandLine.arguments.contains("--demo")
        uid = demo ? "" : defaults.string(forKey: "deviceUID") ?? ""
        channel = demo ? 1 : max(1, defaults.integer(forKey: "channel"))
        mode = demo ? .music : defaults.string(forKey: "detectionMode").flatMap(DetectionMode.init(rawValue:)) ?? .music
    }

    func run() {
        queue.async {
            self.refresh()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(100))
            timer.setEventHandler {
                self.ticks += 1
                if self.ticks % 20 == 0 { self.refresh() }
                self.publish()
            }
            self.timer = timer
            timer.resume()
        }
        DispatchQueue.global().async {
            while let line = readLine() {
                guard let data = line.data(using: .utf8), let command = try? JSONDecoder().decode(Command.self, from: data) else { continue }
                self.queue.async { self.handle(command) }
            }
            self.queue.async { self.input.stop { exit(0) } }
        }
    }

    func handle(_ command: Command) {
        switch command.action {
        case "tap": session.tap(at: now)
        case "mode":
            guard let mode = command.mode else { return }
            session.returnToAudio()
            stop()
            self.mode = mode
            if !demo { defaults.set(mode.rawValue, forKey: "detectionMode") }
            ensureListening()
        case "select":
            stop(preserveModel: true)
            if let uid = command.uid, uid != self.uid { self.uid = uid; channel = 1 }
            if let channel = command.channel { self.channel = max(1, min(channel, device?.channels ?? 1)) }
            if !demo {
                defaults.set(uid, forKey: "deviceUID"); defaults.set(channel, forKey: "channel")
            }
            ensureListening()
        default: break
        }
        publish()
    }

    func refresh() {
        input.devices { result in self.queue.async {
            switch result {
            case .success(let devices):
                let previous = self.device
                self.devices = devices
                if self.uid.isEmpty, let first = devices.first { self.uid = first.uid }
                if (self.listening || self.starting) && !self.demo && self.device != previous {
                    self.stop()
                }
                if let device = self.device, self.channel > device.channels { self.channel = 1 }
                self.ensureListening()
            case .failure: self.error = "Couldn’t find audio inputs."
            }
            self.publish()
        } }
    }

    func ensureListening() {
        guard !listening && !starting else { return }
        guard demo || device != nil else { error = "Choose an available input."; return }
        if !demo {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .denied, .restricted: denied(); return
            default: break
            }
        }
        start()
    }

    func start() {
        guard !listening && !starting else { return }
        guard demo || device != nil else { error = "Choose an available input."; return }
        error = nil; session.audioReading = nil
        generation += 1
        let token = generation
        starting = true
        if demo { open(token); return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: open(token)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in self.queue.async {
                guard self.generation == token else { return }
                if granted { self.open(token) } else { self.denied() }
            } }
        default: denied()
        }
    }

    func denied() {
        starting = false
        error = "Allow Tempo Time LIVE in System Settings → Privacy & Security → Microphone."
        publish()
    }

    func open(_ token: Int) {
        input.start(device: demo ? nil : device, channel: demo ? 1 : channel, settings: DetectorSettings(), mode: mode) { update in
            self.queue.async {
                guard self.generation == token else { return }
                switch update {
                case .started: self.starting = false; self.listening = true
                case .measurement(let snapshot, let peak, let clipped, let onsets):
                    if clipped { self.clippedTime = self.now }
                    if onsets > 0 && !self.demo {
                        self.beatSequence += onsets
                        self.lastBeatTime = snapshot.lastBeatTime ?? self.now
                    }
                    self.songStatus = snapshot.songStatus
                    self.session.audioReading = snapshot.reading
                    // Hold brief clicks long enough for the UI's 100 ms polling interval.
                    if peak >= self.peakDB || self.now - self.peakTime > 0.2 {
                        self.peakDB = peak.isFinite ? max(-120, min(0, peak)) : -120
                        self.peakTime = self.now
                    }
                case .failed(let message): self.stop(); self.error = message
                }
                self.publish()
            }
        }
    }

    func stop(preserveModel: Bool = false) {
        generation += 1
        input.stop(preserveModel: preserveModel)
        clippedTime = -Double.infinity
        listening = false; starting = false; session.audioReading = nil; error = nil
        peakDB = -120; peakTime = 0; lastBeatTime = 0; songStatus = nil
    }

    func publish() {
        let time = now
        let manual = session.isManual(at: time)
        let reading = session.reading(at: time)
        let pulse = reading?.pulseMilliseconds
        let stale = !manual && reading?.isStale == true
        let visiblePulse = stale ? nil : pulse
        let status = manual ? "Manual" : starting ? "Connecting"
            : songStatus ?? (stale ? "No signal" : listening ? "Audio" : "Waiting for audio")
        var value: [String: Any] = [
            "devices": devices.map { ["uid": $0.uid, "name": $0.name, "channels": $0.channels] },
            "uid": uid, "channel": channel, "listening": listening, "starting": starting,
            "manual": manual, "mode": mode.rawValue, "status": status,
            "beatSequence": beatSequence,
            "beatTime": lastBeatTime > 0 ? (Date().timeIntervalSince1970 - (time - lastBeatTime)) * 1000 as Any : NSNull(),
            "beatActive": !manual && listening && time - lastBeatTime < 0.2,
            "clipped": listening && time - clippedTime < 0.2,
            "peakDB": listening && time - peakTime < 0.5 ? peakDB : -120,
            "bpm": visiblePulse.map { 60000 / $0 } as Any? ?? NSNull(),
            "pulse": visiblePulse as Any? ?? NSNull()
        ]
        value["error"] = error as Any? ?? NSNull()
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), data != lastJSON else { return }
        lastJSON = data
        FileHandle.standardOutput.write(data + Data([10]))
    }
}
let service = Service()
service.run()
dispatchMain()
