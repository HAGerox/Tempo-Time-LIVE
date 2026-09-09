"""Build-time download with pinned hashes; installers contain both models."""
import hashlib
import json
from pathlib import Path
import urllib.request

root = Path(__file__).resolve().parents[1]
destination = root / '.build/live-models'
destination.mkdir(parents=True, exist_ok=True)
for item in json.loads((root / 'audio_runtime/models.json').read_text()):
    path = destination / item['name']
    if path.exists() and hashlib.sha256(path.read_bytes()).hexdigest() == item['sha256']:
        continue
    print('Downloading', item['name'], flush=True)
    with urllib.request.urlopen(item['url'], timeout=120) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != item['sha256']:
        raise RuntimeError('Model checksum mismatch: ' + item['name'])
    temporary = path.with_suffix(path.suffix + '.part')
    temporary.write_bytes(data)
    temporary.replace(path)
