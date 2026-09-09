# Testing

`npm test` builds the audio helper and runs the Swift engine suite plus a real
helper-protocol test. The protocol test includes a 30-second wait to verify
that manual tapping returns to the current audio reading. Fixtures are
synthetic and do not access the microphone.

`bash scripts/build-macos.sh` additionally builds the production Tauri app,
checks its signed helper and bundled model runtimes with a system-only PATH,
then creates an unsigned DMG.
The GitHub workflow also runs Clippy, formatter checks, CLI integration,
the sanitized C queue stress test, and tests the helper inside the app bundle.

Before publishing an installer, verify:

- First launch with fresh preferences and microphone permission denied/allowed.
- Representative music through the selected device/channel. Confirm the music
  tempo and visible pulses after the eight-second history has filled.
- An isolated audio click through the selected device and channel, including
  high channel numbers. At 120 quarter-note BPM, expect 500 ms per quarter
  note and 62.50 ms per thirty-second note.
- Tap override and automatic return after 30 seconds, automatic capture on launch/channel changes and quit.
- Input disconnect, sample-rate changes, sleep/wake and recovery.
- Window sizing, both appearances, keyboard access and VoiceOver.
- The actual downloaded app on the advertised architecture and macOS baseline.

Automated PCM tests and a successful CI build are not hardware validation.

## Initial release verification

On Apple Silicon with macOS 15.7.7, the native suite passed 65 tests (one
opt-in real-worker test skipped), alongside eight pulse-clock tests, 22 CLI
cases, the concurrent queue stress test and the 30-second service integration
check. A separate real-worker music test exercised the updated runtime: first
accepted review at 9.24 seconds, median 95.90 BPM against an approximately
98 BPM reference. Rate reset, silence, stale review rejection and EOF passed.
This is a regression check, not a published accuracy benchmark.

macOS 14 is the bundled libraries' deployment minimum; it has not been tested
on a separate macOS 14 machine. Dante hardware and sleep/wake testing are not
claimed by these checks.

The packaged app was also exercised with real music through BlackHole loopback:
selected-channel level and tempo appeared, keyboard tapping entered Manual,
then the app returned to Audio and cleared the reading on silence. Screenshots
in `assets/screenshots` document the actual desktop build. The separate bundled
worker passed the same real-music check with a system-only PATH (first review
9.33 seconds, median 95.90 BPM, maximum PCM reply 55.3 ms). App/helper/runtime
signatures and the unsigned DMG checksum were verified locally.
