#!/usr/bin/env python3
"""Regenerate the app icon files from assets/AppIcon.png (1024x1024 master; AppIcon.svg is its vector source).
Uses the repo's Tauri CLI; generated PNG/ICO/ICNS assets are committed.
"""
import shutil
import subprocess
import tempfile
from pathlib import Path
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as out:
    subprocess.run(['npx', 'tauri', 'icon', str(root / 'assets/AppIcon.png'), '-o', out], cwd=root, check=True)
    for name in ('icon.png', 'icon.ico', 'icon.icns'):
        shutil.copy(Path(out) / name, root / 'src-tauri/icons' / name)
    shutil.copy(Path(out) / 'icon.icns', root / 'assets/AppIcon.icns')
