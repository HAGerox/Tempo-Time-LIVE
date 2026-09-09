"""Collect notices for the actual installed runtime distributions, without local paths."""
from importlib.metadata import distributions
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
output = root / '.build/runtime-notices' / sys.argv[1]
output.mkdir(parents=True, exist_ok=True)
sections = [(root / 'audio_runtime/NOTICE.md').read_text()]
for distribution in sorted(distributions(), key=lambda d: d.metadata['Name'].lower()):
    sections.append(f"\n{distribution.metadata['Name']} {distribution.version}\n")
    if distribution.metadata['Name'].lower() == 'madmom':
        sections.append((root / 'assets/licenses/Madmom-BSD.txt').read_text())
        continue  # Unused madmom model data has a different licence and is excluded.
    for file in distribution.files or []:
        if any(word in file.name.lower() for word in ('license', 'copying', 'notice')):
            path = Path(distribution.locate_file(file))
            if path.is_file():
                sections.append(str(file) + '\n' + path.read_text(errors='replace'))
license_path = Path(sys.base_prefix) / 'lib/python3.11/LICENSE.txt'
if license_path.exists():
    sections.append(license_path.read_text())
sections.append((root / 'assets/licenses/BeatNet-CC-BY-4.0.txt').read_text())
(output / 'THIRD_PARTY.txt').write_text('\n'.join(sections))
