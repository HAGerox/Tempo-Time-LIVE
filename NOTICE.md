# Notices

Tempo Time LIVE and its original icon are copyright © 2026 Finn Stanley, under the MIT license in LICENSE.

This macOS app starts from [HAGerox/utility-app-template](https://github.com/HAGerox/utility-app-template), commit `12cf6445a8c421ebae03d5441685ad584676d372`. Its Tauri starter, design guidance, project instructions, packaging scripts and workflow were adapted here. The original Tempo Time palette, icon and interaction informed the macOS version.

The interface bundles React (MIT) and Tauri (MIT or Apache-2.0), with their dependency trees pinned in package-lock.json and Cargo.lock. Foundation, AVFoundation, Core Audio, AudioToolbox, SoundAnalysis and WebKit are supplied by macOS. Dante and Dante Virtual Soundcard are Audinate trademarks. This app uses Core Audio; it does not bundle, implement or license Dante networking software.

The packaged app includes THIRD_PARTY.txt with license notices and source-package links for its macOS dependencies. The source repository includes pinned upstream license copies where crate archives omit them.

The live audio runtime uses BeatNet/BeatNet+ under CC BY 4.0 and Beat This! under
MIT. See [audio runtime attribution](audio_runtime/NOTICE.md). Only required
inference modules are vendored; model weights are downloaded with verified hashes
at build time and included in the installer. Python/runtime dependency licence
texts are generated into each frozen runtime. Madmom's pretrained model data is
not needed by this architecture and is excluded from the bundle.
