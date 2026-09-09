# Audio runtime attribution

BeatNet cascade particle filtering is by Mojtaba Heydari, from
https://github.com/mjhydri/BeatNet, revision
`81cedd4beeb7235262db80969a0c9ce9a48a0ed4`, under CC BY 4.0.

BeatNet+ inference and non-percussive weights are by Mojtaba Heydari and Zhiyao
Duan, from https://github.com/mjhydri/BeatNet-Plus, revision
`bb90eb0a9065b101a4b4c4cb2b2061950266cb4b`. Permission to distribute under the
same CC BY 4.0 terms as BeatNet was obtained from the maintainer. The shared
licence text is `assets/licenses/BeatNet-CC-BY-4.0.txt`. Upstream inference modules
retain their original inference logic (whitespace normalized); original example audio, training datasets and unused
model weights are omitted. No endorsement is implied.

Beat This! 1.1.0 and its `final0` model are by Francesco Foscarin, Jan Schlüter
and Gerhard Widmer: https://github.com/CPJKU/beat_this. Code and weights are MIT
licensed. The installed distribution's MIT copyright/licence text is included
in the bundled runtime notices.

Tempo Time LIVE's adapters add selected-channel streaming, silence resets,
bounded background work, an eight-second evidence fit and audio-clock phase
handoffs. These adapters use the repository's MIT licence. Third-party licences
remain applicable to their respective components; the application's MIT licence
does not relicense its dependencies or model weights.
