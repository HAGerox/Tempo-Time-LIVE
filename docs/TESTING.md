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
- Speech, noise, silence and transitions in each selected mode:
  speech and silence must clear tempo while the meter stays live. Music mode must
  require music evidence; Click track assumes an isolated click source.
  Vocal music should retain tracking. A returning song must not reuse a tempo
  or review from the preceding passage.
- An isolated audio click through the selected device and channel, including
  high channel numbers. At 120 quarter-note BPM, expect 500 ms per quarter
  note and 63 ms per thirty-second note (rounded from 62.5 ms).
- Tap override and automatic return after 30 seconds, automatic capture on launch/channel changes and quit.
- Input disconnect, sample-rate changes, sleep/wake and recovery.
- Window sizing, both appearances, keyboard access and VoiceOver.
- The actual downloaded app on the advertised architecture and macOS baseline.

Automated PCM tests and a successful CI build are not hardware validation.

The content gate has deterministic policy and worker-protocol tests. To exercise
system music/speech classification and native click timing on local mono WAVs:

```sh
TEMPO_CONTENT_FIXTURES=/path/to/fixtures swift test --filter SoundContentAnalyzerTests
```

`music-` fixtures require music recognition; `click-` fixtures require stable native
click readings after the speech veto clears. `speech-` fixtures must suppress both.
Short recordings repeat to at least 12 seconds, so acquisition delay cannot hide
false readings. Set `TEMPO_CONTENT_CLICK_BPM` when all clicks share a known tempo.
Include real DAW clicks, accents, gain changes, noise, speech, music and silence.
Broad environmental fixtures deliberately flag residual false readings with Click
track selected for the wrong kind of source; this is not automatic source recognition.
Fixtures remain local. The `TEMPO_TEST_BEATNET_WORKER`, `TEMPO_TEST_SONG` and
`TEMPO_TEST_BPM` real music-engine test still accepts zero to require no tempo.

Verify mode persistence, no music-to-click fallback, clearing tempo/phase during
mode changes, rapid switching, and selecting either source while Manual is active.
Confirm Click track starts without loading the music runtime. Check the Music /
Click track switch below the circle at minimum and large sizes; the existing TAP
caption should become MANUAL while tapping.

## Music / Click track selection checks

Local checks on 11 September 2026 passed 77 native tests (two opt-in tests skipped),
eight pulse-clock tests, and the service protocol tests including the real
30-second timeout and selecting/reselecting a source during manual override.
After the final startup-error handling change, the affected music adapter tests
were rerun successfully.

All 30 ordinary Pro Tools Click II sounds passed at 120 BPM. Six real accented
sounds passed at each of 60, 120, 180 and 240 BPM. The music/speech fixture run
passed six music excerpts, twenty speech excerpts, generated clicks, noise, a
steady tone and silence. These are local compatibility checks, not a claim of
universal recognition or Dante hardware support.

Real Core Audio/BlackHole checks passed Logic's default click and Pro Tools MPC
click at 120 BPM, speech/noise suppression in each mode, music around 131 BPM,
and music returning after speech/noise. The Tauri app was checked at minimum and
large sizes, during manual override, on mode selection and restart, and for
recovery into Click track when the music worker was deliberately unavailable.
The click path ran without launching the music worker. The custom metronome
model and its training/bundling machinery have been removed.

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
