# Tempo Time LIVE

Follow the beat of live music and read note lengths in milliseconds.

Choose an audio input and channel. Tempo Time LIVE estimates the tempo locally,
pulses with the music and shows six note lengths, from whole to thirty-second.
It starts tracking automatically; its background analysis becomes available after
roughly nine seconds of music. Audio is not recorded or uploaded.

You can still tap the circle or press Space for a manual tempo. After 30 seconds
without a tap, the display returns to audio tracking automatically.

Requires an **Apple Silicon Mac with macOS 14 or later**. Allow microphone access
when macOS asks. The app includes its models and runtimes; no Python, Homebrew or
other developer tools are needed. Initial releases are ad-hoc signed and not
notarized. Ambiguous music can still produce half/double tempo or missed beats.

[Download for macOS](https://github.com/HAGerox/Tempo-Time-LIVE/releases/latest/download/tempo-time-live-macOS.dmg)

## Development

The app uses the shared Tauri + React + TypeScript utility template with a Swift
Core Audio service. Development requires Node 22+, Rust, Xcode/Swift 6 and uv.

```sh
npm ci
npm run dev
```

The first development launch prepares pinned Python runtimes and verifies model
downloads. Build the self-contained app and installer with:

```sh
bash scripts/build-macos.sh
```

`npm test` runs the native engine and service tests; `npm run test:pulse` checks
the visual clock. See [architecture](ARCHITECTURE.md), [release process](RELEASE.md)
and [testing](docs/TESTING.md). The application's original code is MIT licensed;
[third-party notices](NOTICE.md) describe the separately licensed components.
