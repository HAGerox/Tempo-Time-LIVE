#!/usr/bin/env python3
"""Exercise a bundled runtime with a clean PATH and bounded protocol deadlines.

Optional mono PCM16 WAV input is streamed in real time. Audio stays local and
only timing/tempo aggregates are printed. No recording belongs in the repo.
"""
import argparse
import array
import base64
import json
import os
from pathlib import Path
import select
import statistics
import subprocess
import tempfile
import time
import wave

parser = argparse.ArgumentParser()
parser.add_argument('executable', type=Path)
parser.add_argument('--audio', type=Path)
parser.add_argument('--seconds', type=float, default=20)
parser.add_argument('--expected-bpm', type=float)
args = parser.parse_args()
rate = 44100
samples = None
if args.audio:
    with wave.open(str(args.audio), 'rb') as source:
        assert source.getnchannels() == 1 and source.getsampwidth() == 2, 'Use mono PCM16 WAV'
        rate = source.getframerate()
        samples = array.array('h', source.readframes(round(args.seconds * rate)))
        if os.sys.byteorder != 'little':
            samples.byteswap()

env = {'PATH': '/usr/bin:/bin', 'HOME': os.environ['HOME'], 'TMPDIR': tempfile.gettempdir()}
with tempfile.TemporaryDirectory() as directory:
    process = subprocess.Popen([str(args.executable.resolve())], cwd=directory, env=env,
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    pending = bytearray()
    def request(value, timeout=5):
        process.stdin.write(json.dumps(value).encode() + b'\n')
        process.stdin.flush()
        deadline = time.monotonic() + timeout
        while b'\n' not in pending:
            remaining = deadline - time.monotonic()
            assert remaining > 0 and select.select([process.stdout], [], [], remaining)[0], 'Runtime timeout'
            part = os.read(process.stdout.fileno(), 65536)
            assert part, 'Runtime disconnected'
            pending.extend(part)
        line, _, rest = pending.partition(b'\n')
        pending[:] = rest
        result = json.loads(line)
        assert 'error' not in result, result
        return result
    def pcm(values):
        block = array.array('f', values)
        if os.sys.byteorder != 'little':
            block.byteswap()
        return {'pcm': base64.b64encode(block.tobytes()).decode()}
    try:
        assert request({'rate': rate}, 120)['backgroundReview']
        latencies, tempos = [], []
        first_review = None
        if samples is not None:
            start = time.monotonic()
            for offset in range(0, len(samples), 2048):
                before = time.monotonic()
                result = request(pcm(v / 32768 for v in samples[offset:offset + 2048]))
                latencies.append(time.monotonic() - before)
                if result['review']:
                    tempos.append(60 / result['review']['period'])
                    if first_review is None:
                        first_review = offset / rate
                remaining = start + min(offset + 2048, len(samples)) / rate - time.monotonic()
                if remaining > 0:
                    time.sleep(remaining)
            assert tempos, 'No accepted background reviews'
            assert first_review < 12, 'Background review arrived late'
            assert max(latencies) < 2, 'PCM replies blocked on background inference'
            median = statistics.median(tempos)
            if args.expected_bpm:
                assert abs(median - args.expected_bpm) < 6, median
            print(json.dumps({'first_review_seconds': first_review, 'median_bpm': median,
                              'max_reply_ms': max(latencies) * 1000}))
        # Reset invalidates every old review, including jobs still in flight.
        assert request({'rate': 48000})['ready']
        for _ in range(24):
            result = request(pcm([0.0] * 2048))
            assert result['review'] is None
        assert result['silent']
        process.stdin.close()
        assert process.wait(timeout=10) == 0
        print('Bundled runtime: initialization, rate reset, silence and EOF passed with a system-only PATH.')
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        errors = process.stderr.read().decode(errors='replace')
        if process.returncode:
            raise RuntimeError(errors[-2000:])
