#!/usr/bin/env python3
"""Reject accidental local/private material in files intended for publication.

This complements (rather than replaces) dedicated secret scanners and review.
It never prints matching content, which may itself be sensitive.
"""
import json
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
paths = subprocess.check_output(
    ['git', 'ls-files', '-co', '--exclude-standard', '-z'], cwd=root
).decode().split('\0')
patterns = {
    'personal absolute path': re.compile(r'/(?:Users|home)/[^/\s"<>]+/'),
    'local Windows path': re.compile(r'[A-Z]:\\Users\\[^\\\s]+\\'),
    'private network address': re.compile(r'\b(?:192\.168\.\d{1,3}\.\d{1,3}|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})\b'),
    'session checkpoint reference': re.compile(r'refs/' + r't3/checkpoints/'),
}
blocked = {'.env', '.DS_Store', 'credentials.json', 'id_rsa', 'id_ed25519'}
blocked_extensions = {'.pem', '.key', '.p12', '.pfx', '.jks', '.keystore', '.mobileprovision', '.dmg', '.zip', '.wav', '.mp3'}
findings = []
checked = 0
for name in sorted(set(paths)):
    if not name:
        continue
    path = root / name
    if path.is_symlink():
        if not path.resolve().is_relative_to(root):
            findings.append((name, 'symlink escapes repository'))
        continue
    if not path.is_file():
        continue
    checked += 1
    if path.name in blocked or path.suffix in blocked_extensions:
        findings.append((name, 'private/generated file type'))
    if path.stat().st_size > 5 * 1024 * 1024:
        findings.append((name, 'large file needs explicit review'))
    data = path.read_bytes()
    if data[:4] in (bytes.fromhex('cffaedfe'), bytes.fromhex('feedfacf'), bytes.fromhex('cafebabe')):
        findings.append((name, 'compiled executable'))
    if b'\0' in data:
        continue
    text = data.decode('utf-8', errors='replace')
    for label, pattern in patterns.items():
        if pattern.search(text):
            findings.append((name, label))

commits = subprocess.run(['git', 'log', '--all', '--format=%H%x00%ae%x00%ce%x00%B%x00'],
                         cwd=root, capture_output=True, text=True)
if commits.returncode == 0:
    for record in commits.stdout.split('\0'):
        if ('@' in record and '\n' not in record
                and not record.endswith('@users.noreply.github.com')
                and record != 'noreply@github.com'):
            findings.append(('commit metadata', 'non-GitHub-noreply email'))
        if patterns['session checkpoint reference'].search(record):
            findings.append(('commit metadata', 'session checkpoint reference'))

print(json.dumps({'files_checked': checked, 'findings': findings}, indent=2))
raise SystemExit(bool(findings))
