"""Build-time downloads with pinned hashes; installers contain both models."""
import hashlib
import json
from pathlib import Path
import time
import urllib.error
import urllib.request


def download(url):
    if not url.startswith('https://'):
        raise ValueError('Model downloads require HTTPS')
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=120) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            if error.code not in {429, 500, 502, 503, 504} or attempt == 3:
                raise
        except (urllib.error.URLError, TimeoutError):
            if attempt == 3:
                raise
        time.sleep(2 ** attempt)


root = Path(__file__).resolve().parents[1]
destination = root / '.build/live-models'
destination.mkdir(parents=True, exist_ok=True)
for item in json.loads((root / 'audio_runtime/models.json').read_text()):
    path = destination / item['name']
    if path.exists() and hashlib.sha256(path.read_bytes()).hexdigest() == item['sha256']:
        continue
    print('Downloading', item['name'], flush=True)
    last_error = None
    for url in [item['url'], *item.get('mirrors', [])]:
        try:
            data = download(url)
        except (urllib.error.URLError, TimeoutError) as error:
            last_error = error
            continue
        if hashlib.sha256(data).hexdigest() != item['sha256']:
            raise RuntimeError('Model checksum mismatch: ' + item['name'])
        break
    else:
        raise RuntimeError('All model download locations failed: ' + item['name']) from last_error
    temporary = path.with_suffix(path.suffix + '.part')
    temporary.write_bytes(data)
    temporary.replace(path)
