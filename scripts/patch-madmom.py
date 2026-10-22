#!/usr/bin/env python3
"""Replace madmom's version-only pkg_resources use with stdlib metadata."""
from pathlib import Path

path = Path('.build/live-foreground-venv/lib/python3.11/site-packages/madmom/__init__.py')
text = path.read_text()
if 'import pkg_resources' in text:
    replacements = {
        'import pkg_resources': 'from importlib.metadata import version',
        'pkg_resources.get_distribution("madmom").version': 'version("madmom")',
        'del pkg_resources, doctest': 'del version, doctest',
    }
    for old, new in replacements.items():
        if text.count(old) != 1:
            raise SystemExit(f'Unexpected madmom source; missing unique {old!r}')
        text = text.replace(old, new)
    path.write_text(text)
print('madmom uses importlib.metadata; obsolete pkg_resources is unnecessary.')
