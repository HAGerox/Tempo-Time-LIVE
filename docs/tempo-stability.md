# Audio tempo stability

Implemented September 12, 2026. The target is a steady reading with roughly ten
seconds allowed for a song change. This is not a worst-case latency guarantee:
ambiguous music, missing beats and very slow click tracks can take longer.

## Policy

`TempoLock` is a pure Swift publication policy after audio detection. Both music
sources and the native Click track path use it; manual tapping does not.

- Nearby estimates (within 2.5%) use a three-second median, a 0.4 BPM dead band
  and a two-second exponential smoothing time constant.
- A different candidate must remain consistent within 2.5% for three seconds.
  Candidates within about 6% of half/double tempo need five seconds instead.
- Distinct audio timestamps confirm a candidate. Repeated replies cannot advance
  confirmation or renew evidence. Gaps and inconsistent candidates break confirmation.
- Strong background fits expose their earliest supporting beat. The native policy
  credits up to five seconds of that existing audio, once, and still requires three
  fresh observations. This avoids adding the full confirmation period after the
  model has already analysed a long passage. Weak fits receive no history credit.
- Changes are committed directly to the supported candidate, without averaging two
  unrelated tempos. Unconfirmed candidates do not change beat phase.
- Missing evidence expires the display; ten seconds without support for the held
  tempo also expires it. Content suppression and stream/input/mode resets clear it.

History credit requires review quality >= 0.8, support >= 0.85, and a finite start
within the review's eight-second window and permitted music segment. Quality is
beat evidence, not a calibrated probability that the musical tempo is correct.

## Before/after comparison

The baseline was the unchanged Git HEAD `132703c` at the start of the task. Record model
replies once in real time, then replay the exact same replies through both native
implementations. The replay supplies music permission explicitly, isolating the
publication policy from asynchronous classification. Local recordings and raw
traces remain in ignored `.build/` directories.

| Input | Duration | Baseline integer BPM changes | Updated integer BPM changes |
| --- | ---: | ---: | ---: |
| Piano excerpt | 20 s | 19 | 1 |
| Drum excerpt | 20 s | 12 | 1 |
| Full music excerpt | 20 s | 6 | 1 |
| Piano followed by drums, without silence | 40 s | 41 | 5 |

Counts compare adjacent published readings rounded to whole BPM; gaps are excluded.
They include useful corrections of an initially wrong estimate. These are stability
measurements, not a representative genre-wide tempo-accuracy benchmark.

The last example changes source at 20 seconds. The baseline first reaches the
approximately 71 BPM interpretation at 27.25 seconds, but later jumps back to about
140 BPM. The updated output reaches approximately 71 BPM at 29.3 seconds (9.3 seconds
after the change), and retains it through the end. It briefly publishes about
140 BPM before that correction. Initial half/double ambiguity is not eliminated.

Native synthetic click transitions, including onset detection and interval fitting:
120→90 takes 6 seconds; 120→60 takes 9 seconds; 120→240 takes 6 seconds. These tests
also reject invented intermediate tempos. Synthetic PCM does not validate Dante
hardware.

## Reproduction

Record local mono PCM16 WAV inputs using the development or bundled music worker:

```sh
python3 scripts/record-tempo-evidence.py .build/live-dev/tempo-live \
  .build/tempo-stability-traces /path/to/music.wav
TEMPO_TEST_EVIDENCE="$PWD/.build/tempo-stability-traces" \
TEMPO_TEST_EVIDENCE_OUTPUT="$PWD/.build/tempo-stability-results/updated" \
  swift test --filter TempoEvidenceReplayTests
```

For a baseline comparison, put the same replay test in an isolated baseline checkout
and point it at the same trace directory. Exported JSON contains time and published
BPM for each block. Do not record a second model run and call that identical evidence.

Run `npm test` for native and service tests, including the real 30-second manual
timeout, and `npm run test:pulse` for visual clock tests. `TempoLockTests` covers
jitter, brief octave errors, sustained changes, gradual ramps, duplicate/out-of-order
observations, expiry, reset, unsupported gaps and overlapping-review history credit.

## Live verification

The native Tauri preview displayed 131 BPM and matching note lengths from real
piano audio through BlackHole channel 1. The current audio service also passed
loopback checks for synthesized, Logic and Pro Tools clicks (120 BPM), music
(about 131 BPM), speech/noise rejection, door-knock rejection in Music mode, and
music reacquisition after those interruptions. The test feed was stopped before
handoff. This is local Core Audio loopback coverage, not Dante hardware validation.

The native suite completed 87 tests with three optional integration tests skipped;
the recorded-evidence test was then run explicitly. Service/manual-timeout and
pulse-clock checks passed. One service startup timed out while concurrent builds
and model runs were active; a standalone rerun passed. Fresh preference overrides
started in Music on channel 1 without inheriting a BPM or manual override. Existing
OS microphone permission was used; permission was not revoked or reset.
