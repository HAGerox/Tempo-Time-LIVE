#!/usr/bin/env python3
"""Verify the actual Tauri bundle and its self-contained audio service."""
from pathlib import Path
import plistlib
import subprocess
import sys
app = Path(sys.argv[1]).resolve()
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert info['NSMicrophoneUsageDescription']
assert info['CFBundleIdentifier'] == 'io.github.hagerox.tempotime.live'
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
for name in [info['CFBundleExecutable'], 'tempo-service']:
    binary = app / 'Contents/MacOS' / name
    assert binary.is_file(), binary
    subprocess.run(['codesign', '--verify', '--strict', str(binary)], check=True)
    print(name, subprocess.check_output(['lipo', str(binary), '-archs'], text=True).strip())
    libraries = subprocess.check_output(['otool', '-L', str(binary)], text=True)
    commands = subprocess.check_output(['otool', '-l', str(binary)], text=True)
    for line in libraries.splitlines():
        if not line.startswith('\t'): continue
        dependency = line.strip().split(' (', 1)[0]
        if dependency.startswith(('/System/Library/', '/usr/lib/')): continue
        if dependency.startswith('@rpath/libswift') and 'path /usr/lib/swift ' in commands: continue
        raise SystemExit(f'Unexpected unbundled dependency: {dependency}')
runtime = app / 'Contents/Resources/runtime'
for name in ('tempo-live', 'tempo-review'):
    executable = runtime / name / name
    assert executable.is_file(), executable
    subprocess.run(['codesign', '--verify', '--strict', str(executable)], check=True)
assert (runtime / 'tempo-live/_internal/models/beatnet-plus-af.pt').is_file()
assert (runtime / 'tempo-review/_internal/models/beat-this-final0.ckpt').is_file()
assert info['LSMinimumSystemVersion'] == '14.0'
print('App, audio service, both model runtimes, bundled weights, signatures and microphone description verified.')

# Prevent accidental build-path disclosures and unused model redistribution.
for path in app.rglob('*'):
    if path.is_file() and not path.is_symlink():
        data = path.read_bytes()
        # Public upstream CI paths are not the app builder's personal data.
        inspected = data.replace(b'/' + b'Users/runner/work/', b'/upstream/').replace(b'/' + b'home/runner/work/', b'/upstream/')
        if str(Path.home()).encode() + b'/' in inspected:
            raise SystemExit(f'Local build path remains in {path.relative_to(app)}')
madmom = runtime / 'tempo-live/_internal/madmom'
assert not any(p.suffix in {'.pkl', '.npz', '.npy', '.h5'} for p in madmom.rglob('*'))
print('Bundle privacy scan and unused-model exclusion passed.')
