#!/usr/bin/env python3
"""Wrap an already signed app in an unsigned DMG."""
from pathlib import Path
import subprocess
import sys
import tempfile

if len(sys.argv) != 3:
    raise SystemExit('Usage: python3 scripts/package-macos-dmg.py App.app output.dmg')
app, output = (Path(value).resolve() for value in sys.argv[1:])
if not app.is_dir() or app.suffix != '.app':
    raise SystemExit('Expected an app bundle')
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
output.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='utility-dmg-') as temporary:
    stage = Path(temporary)
    subprocess.run(['ditto', str(app), str(stage / app.name)], check=True)
    (stage / 'Applications').symlink_to('/Applications')
    subprocess.run(['hdiutil', 'create', '-volname', app.stem, '-srcfolder', str(stage), '-format', 'ULFO', '-ov', str(output)], check=True)
subprocess.run(['hdiutil', 'verify', str(output)], check=True)
signature = subprocess.run(['codesign', '--display', str(output)], capture_output=True, text=True)
if signature.returncode == 0 or 'not signed at all' not in signature.stderr:
    raise SystemExit('Expected an unsigned DMG; refusing to publish an unexpected signature state')
print(output)
