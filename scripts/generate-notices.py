#!/usr/bin/env python3
"""Bundle dependency notices without leaking local manifest paths."""
import json
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
metadata = json.loads(subprocess.check_output([
    'cargo', 'metadata', '--manifest-path', str(root / 'src-tauri/Cargo.toml'),
    '--locked', '--format-version', '1', '--filter-platform',
    next(line.split(': ', 1)[1] for line in subprocess.check_output(['rustc', '-vV'], text=True).splitlines() if line.startswith('host: '))
]))
active = {node['id'] for node in metadata['resolve']['nodes']}
fallbacks = json.loads((root / 'assets/licenses/upstream.json').read_text())
sections = ['Third-party software notices\n\nIncludes macOS runtime and build dependencies. Source packages are linked below.\n']
missing = []

def license_files(folder):
    return sorted(p for p in folder.iterdir() if p.is_file() and p.name.lower().startswith(('license', 'licence', 'copying', 'copyright', 'notice')))

for package in sorted(metadata['packages'], key=lambda p: (p['name'], p['version'])):
    if package['id'] not in active or package['source'] is None:
        continue
    name, version = package['name'], package['version']
    folder = Path(package['manifest_path']).parent
    files = license_files(folder)
    license_file = package.get('license_file')
    if license_file:
        extra = (folder / license_file).resolve()
        if extra.is_relative_to(folder) and extra.is_file() and extra not in files:
            files.append(extra)
    sections.append(f'\n{"=" * 72}\n{name} {version}\nLicense: {package.get("license") or "See license text"}\nSource: https://crates.io/crates/{name}/{version}\n')
    for file in files:
        sections.append(file.read_text(errors='replace'))
    if not files:
        entries = fallbacks.get(name + '@' + version, [])
        if not entries:
            missing.append(name + '@' + version)
        for entry in entries:
            sections.extend([entry['source'], (root / 'assets/licenses' / entry['path']).read_text()])

lock = json.loads((root / 'package-lock.json').read_text())
for path, package in sorted(lock['packages'].items()):
    if not path or package.get('dev') or package.get('optional'):
        continue
    folder = root / path
    manifest = json.loads((folder / 'package.json').read_text())
    name = manifest['name']
    sections.append(f'\n{"=" * 72}\n{name} {manifest["version"]}\nSource: https://www.npmjs.com/package/{name}/v/{manifest["version"]}\n')
    files = license_files(folder)
    if not files:
        missing.append(name)
    for file in files:
        sections.append(file.read_text(errors='replace'))
if missing:
    raise SystemExit('Missing dependency license text: ' + ', '.join(missing))
out = root / 'src-tauri/notices/THIRD_PARTY.txt'
out.parent.mkdir(exist_ok=True)
out.write_text('\n\n'.join(sections))
print('Generated third-party notices with source links.')
