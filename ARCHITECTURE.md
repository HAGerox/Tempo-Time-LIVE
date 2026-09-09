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

Silence and device/sample-rate changes invalidate background generations. Warm
model resets do not reload weights. Long work and subprocess I/O remain off the
UI thread and Core Audio callback. Native sparse-click fallback remains tested;
valid music readings take priority. This is Core Audio integration, not a Dante
network-protocol implementation or a claim of Dante hardware validation.

Installers bundle two isolated Python runtimes because the tested models use
isolated dependency environments for their upstream compatibility requirements. PyInstaller freezes both runtimes and their weights;
paths resolve within the app, independently of developer PATH or a working
checkout. Build-time model downloads have pinned SHA256 hashes. The app does
not download models at first launch. Native and model notices travel in the bundle.

The Tauri app is ad-hoc signed and packaged with the shared unsigned-DMG packager.
The selected review runtime raises the minimum macOS version to 14. Apple Silicon
is the build target. The original Tempo Time click-track app remains a separate
repository and product.
