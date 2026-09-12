# Tempo Time LIVE architecture

The UI uses the user's selected Tauri + React + TypeScript utility template.
The approved input/channel lists, level meter, coral pulse circle and six note
rows are preserved. There is no model selector or manual tempo-hint requirement.

- `src/`: presentation and the audio-clock-based `BeatPulseClock`.
- `src-tauri/`: Tauri shell, typed IPC, bundled helper/runtime resolution and lifecycle.
- `Sources/TempoService`: Core Audio permission, selection and capture lifecycle.
- `Sources/TempoInput`, `Sources/AudioBridge`: allocation-free audio callback/queue
  and serial analysis worker. Exactly one selected channel is analysed.
- `Sources/TempoCore`: native detector, musical tracker, note math and manual
  override, which expires after 30 seconds while audio analysis continues.
- `Sources/TempoInput/SoundContentAnalyzer.swift`: macOS's built-in SoundAnalysis
  classifier, fed the same selected-channel PCM on the analysis worker. It uses
  1.5-second windows with approximately half-second updates for music/speech.
  `AudioContentGate` owns confirmation/expiry policy. Music mode requires music
  recognition. Click track mode uses only the speech veto, with source type
  supplied by the user; it does not perform learned metronome classification.
- `Sources/TempoInput/ClickTrackAnalyzer.swift`: native level-envelope onset
  detection and consistent pulse timing, independent of Python/music workers.
- `audio_runtime/foreground.py`: causal BeatNet+ non-percussive CRNN and BeatNet
  particle filter. Stateful soxr resampling, bounded history and silence resets.
- `audio_runtime/review.py`: full Beat This! `final0`, analysing completed trailing
  eight-second windows, discarding 120 ms at each edge.
- `audio_runtime/tracking.py`: flexible beat-pattern fit used in the benchmark.
- `audio_runtime/coordinator.py`: one persistent review subprocess and one pending
  job. Review runs approximately once a second after the history fills. Two
  consistent, sufficiently supported reviews establish background tracking.
  No Tempo-CNN, fading tempo hint or manual guidance is used.

The native tracker stays warm while background review supplies period and phase.
New review IDs supply phase once; expiry restores the foreground anchor. Review
anchors are already corrected audio times. Foreground timestamps have their
40 ms feature-window offset removed. The UI predicts upcoming pulses against
Core Audio host time and stops after three periods plus 80 ms without evidence.
Eight seconds is analysis history, not a fixed playback delay.

`TempoCore/TempoLock` publishes one persistent audio tempo across foreground/review
handover and also stabilizes Click track output. Manual taps still use the original
interval tracker directly. Values within 2.5% use a trailing three-second median,
a 0.4 BPM dead band and two-second exponential smoothing. Other candidates need
three seconds of consistent evidence; near half/double candidates need five.
Confirmation uses advancing audio timestamps, not PCM reply count or wall time.
Review IDs time confirmation separately from fitted beat positions. A review with
quality >= 0.8 and support >= 0.85 can credit its earliest fitted beat (at most five
seconds), but still needs three fresh observations. Overlapping windows do not
accumulate their shared duration. Foreground-only candidates need four observations.
Pending tempo changes cannot steer phase. Missing evidence expires publication;
conflicting evidence cannot retain an unsupported tempo beyond ten seconds. Silence,
speech suppression, mode/input changes and stream resets clear the lock. Ten seconds
is a measured transition target, not a guarantee for ambiguous music or slow clicks.
The model's quality is beat evidence, not a calibrated probability of correct BPM.

`DetectionMode` (`music` / `click`) crosses React, Tauri IPC and the Swift service.
The service persists it, defaults to Music, ends manual override on selection and
invalidates the previous capture generation before starting the new path. Changing
mode clears tempo and phase. Selecting a source during Manual returns to listening;
normal tapping still expires after 30 seconds. The UI uses the existing area under
the circle for the switch and shows MANUAL inside the otherwise caption-free circle.

Music mode requires two windows with music evidence of at least 0.5; continuation
uses 0.35 to tolerate vocals and quiet passages. Speech without music closes the
gate promptly. Suppression resets native music locks and rejects historical review
IDs/anchors. There is no click fallback in Music mode.

Click track mode uses the existing DC-blocked peak envelope, a -30 dBFS onset
threshold, a half-level reset threshold with 4 ms quiet time and an 80 ms retrigger
guard. The interval tracker requires four consistent intervals before publication;
sparse-activity and recent-onset checks suppress sustained signals and stale locks.
A system speech veto closes the click path whenever speech evidence reaches 0.2;
two low-speech windows reopen it. This veto is not positive metronome recognition.
The selected source is assumed to be an isolated click track. Regular nonmusical
pulses can still be counted when the wrong mode/source is selected. Each detected
click is treated as a quarter note; subdivisions can report a multiple of the DAW
BPM. No DAW-specific samples, custom classifier, model download or music worker
are required for Click track mode.

Missing or stale system classification expires after 1.5 seconds; input changes
reset it. The selected-channel meter and manual tapping remain available during
speech. Mode changes stop the old analyzer before starting the new one. Music
workers remain warm across music input/channel changes, but are released on mode
changes. Long work stays off the UI thread and Core Audio callback.
This is Core Audio integration, not Dante network-protocol implementation or
Dante hardware validation.

Installers bundle two isolated Python runtimes because the tested models use
isolated dependency environments for their upstream compatibility requirements. PyInstaller freezes both runtimes and their weights;
paths resolve within the app, independently of developer PATH or a working
checkout. Packaging shares only byte-identical runtime files using relative symlinks
inside the app, then restores the app signature. The isolated Python environments
and library entry paths remain intact; staging must preserve symlinks. Build-time model downloads have pinned SHA256 hashes. The app does
not download models at first launch. Native and model notices travel in the bundle.

The Tauri app is ad-hoc signed and packaged with the shared unsigned-DMG packager.
The selected review runtime raises the minimum macOS version to 14. Apple Silicon
is the build target. The original Tempo Time click-track app remains a separate
repository and product.
