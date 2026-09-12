#!/usr/bin/env python3
"""Share byte-identical runtime files inside an app, then restore its signature.

The isolated Python environments and all entry paths remain intact. Relative
symlinks replace only duplicate files; no model or executable code is changed.
"""
import argparse
from collections import defaultdict
import filecmp
import hashlib
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('app', type=Path)
args = parser.parse_args()
app = args.app.resolve()
runtime = app / 'Contents/Resources/runtime'
if not runtime.is_dir():
    raise SystemExit('App has no bundled runtime directory')

by_size = defaultdict(list)
for path in runtime.rglob('*'):
    if path.is_file() and not path.is_symlink():
        size = path.stat().st_size
        # Small files offer negligible savings; leave notices and metadata in place.
        if size >= 1024 * 1024:
            by_size[size].append(path)

saved = count = 0
for size, paths in by_size.items():
    if len(paths) < 2:
        continue
    by_hash = defaultdict(list)
    for path in sorted(paths, key=lambda p: (len(p.parts), str(p))):
        with path.open('rb') as source:
            digest = hashlib.file_digest(source, 'sha256').hexdigest()
        by_hash[digest].append(path)
    for matches in by_hash.values():
        canonical = matches[0]
        for path in matches[1:]:
            if not filecmp.cmp(canonical, path, shallow=False):
                raise SystemExit('Duplicate-file comparison failed')
            relative = os.path.relpath(canonical, path.parent)
            # Stage the link before replacing the duplicate, keeping its entry path.
            temporary = path.with_name(path.name + '.compact-link')
            if temporary.exists() or temporary.is_symlink():
                raise SystemExit('Unexpected existing compaction link')
            temporary.symlink_to(relative)
            os.replace(temporary, path)
            saved += size
            count += 1

entitlements = Path(__file__).resolve().parents[1] / 'assets/TempoTime.entitlements'
subprocess.run(['codesign', '--force', '--options', 'runtime', '--entitlements',
                str(entitlements), '--sign', '-', str(app)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
print(f'Shared {count} identical runtime copies; saved {saved / 1024**2:.1f} MiB.')
