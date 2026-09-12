#!/usr/bin/env python3
"""Record local music-worker evidence for repeatable native before/after tests.

Usage: record-tempo-evidence.py WORKER OUTPUT_DIRECTORY WAV [WAV ...]
Audio and traces stay local. Feed real-time mono PCM16; no audio enters the repo.
"""
import array
import base64
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import time
import wave

worker, destination, *inputs = sys.argv[1:]
destination = Path(destination)
destination.mkdir(parents=True, exist_ok=True)
process = subprocess.Popen([str(Path(worker).resolve())], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
pending = bytearray()


def request(value, timeout=90):
    process.stdin.write(json.dumps(value).encode() + b'\n')
    process.stdin.flush()
    deadline = time.monotonic() + timeout
    while b'\n' not in pending:
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([process.stdout], [], [], remaining)[0]:
            raise TimeoutError('Music worker timed out')
        part = os.read(process.stdout.fileno(), 65536)
        if not part:
            raise RuntimeError('Music worker disconnected')
        pending.extend(part)
    line, _, rest = pending.partition(b'\n')
    pending[:] = rest
    response = json.loads(line)
    if 'error' in response:
        raise RuntimeError(response['error'])
    return response


try:
    for filename in inputs:
        with wave.open(filename) as audio:
            rate = audio.getframerate()
            assert audio.getnchannels() == 1 and audio.getsampwidth() == 2
            handshake = request({'rate': rate})
            blocks = []
            frames = 0
            start = time.monotonic()
            while data := audio.readframes(round(rate * 0.05)):
                samples = array.array('h', data)
                if sys.byteorder != 'little':
                    samples.byteswap()
                pcm = array.array('f', (s / 32768 for s in samples))
                if sys.byteorder != 'little':
                    pcm.byteswap()
                response = request({'pcm': base64.b64encode(pcm.tobytes()).decode()}, timeout=5)
                blocks.append({'frames': len(samples), 'response': response})
                frames += len(samples)
                time.sleep(max(0, start + frames / rate - time.monotonic()))
            output = destination / (Path(filename).stem + '.json')
            output.write_text(json.dumps({'rate': rate, 'handshake': handshake, 'blocks': blocks}))
            print(output, flush=True)
finally:
    process.stdin.close()
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
