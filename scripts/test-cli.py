#!/usr/bin/env python3
"""Independent PCM fixtures -> real Swift WAV reader -> real detector -> JSON assertions."""
import json
import math
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

binary = Path(sys.argv[1] if len(sys.argv) > 1 else '.build/debug/tempo-analyze').resolve()
checks = 0


def invoke(path, *options, success=True):
    global checks
    result = subprocess.run([str(binary), str(path), *map(str, options)], text=True, capture_output=True)
    assert (result.returncode == 0) == success, result.stderr or result.stdout
    checks += 1
    return json.loads(result.stdout) if success else None


def make_wave(path, channels=2, selected=1, bpm=127.3, rate=48000, bits=16, floating=False,
              quiet=False, stop=False, change=False):
    seconds = 8
    frames = seconds * rate
    width = bits // 8
    pcm = bytearray(frames * channels * width)

    def click(time, channel, index, scale=1):
        first = round(time * rate)
        freq = 1760 if index % 4 == 0 else 880
        for sample in range(int(rate * .025)):
            frame = first + sample
            if frame >= frames:
                break
            phase = sample / rate
            value = scale * .6 * math.exp(-180 * phase) * math.sin(2 * math.pi * freq * phase)
            offset = (frame * channels + channel) * width
            if floating:
                struct.pack_into('<f', pcm, offset, value)
            else:
                integer = round(value * ((1 << (bits - 1)) - 1))
                pcm[offset:offset + width] = integer.to_bytes(width, 'little', signed=True)

    time = .1
    index = 0
    while time < (3 if stop else seconds - .1):
        click(time, selected, index, .01 if quiet else 1)
        time += 60 / (90 if change and time >= 3 else bpm)
        index += 1
    if channels > 1:
        time = .1
        while time < seconds - .1:
            click(time, 0, 1)
            time += 60 / 180
    encoding = 3 if floating else 1
    fmt = struct.pack('<HHIIHH', encoding, channels, rate, rate * channels * width, channels * width, bits)
    body = b'WAVEfmt ' + struct.pack('<I', len(fmt)) + fmt + b'data' + struct.pack('<I', len(pcm)) + pcm
    path.write_bytes(b'RIFF' + struct.pack('<I', len(body)) + body)


with tempfile.TemporaryDirectory(prefix='tempo-fixtures-') as directory:
    root = Path(directory)
    for bits, floating in [(16, False), (24, False), (32, False), (32, True)]:
        path = root / f'click-{bits}-{floating}.wav'
        make_wave(path, bits=bits, floating=floating)
        report = invoke(path, '--channel', 2)
        assert abs(report['pulsesPerMinute'] - 127.3) < .02, report
        assert report['stable'] and not report['stale'], report
        assert abs(report['noteMilliseconds']['1/32'] - 60000 / 127.3 / 8) < .02
        other = invoke(path, '--channel', 1)
        assert abs(other['pulsesPerMinute'] - 180) < .02, other
    path = root / 'channel64.wav'
    make_wave(path, channels=64, selected=63)
    report = invoke(path, '--channel', 64, '--click-unit', 'eighth')
    assert abs(report['quarterNoteBPM'] - 63.65) < .02, report
    silent = invoke(path, '--channel', 32)
    assert silent['detectedClicks'] == 0 and not silent.get('pulseMilliseconds'), silent
    invoke(path, '--channel', 65, success=False)
    path = root / 'quiet.wav'
    make_wave(path, quiet=True)
    silent = invoke(path, '--channel', 2)
    assert silent['detectedClicks'] == 0
    quiet = invoke(path, '--channel', 2, '--threshold', -55)
    assert abs(quiet['pulsesPerMinute'] - 127.3) < .02
    path = root / 'stopped.wav'
    make_wave(path, stop=True)
    stopped = invoke(path, '--channel', 2)
    assert stopped['stale'] and not stopped['stable'], stopped
    path = root / 'tempo-change.wav'
    make_wave(path, change=True)
    changed = invoke(path, '--channel', 2)
    assert abs(changed['pulsesPerMinute'] - 90) < .02 and changed['stable'], changed
    path = root / 'invalid.wav'
    path.write_bytes(b'not audio')
    invoke(path, success=False)
    invoke('--demo', '--channel', 0, success=False)
    invoke('--demo', '--threshold', 'nan', success=False)
    invoke('--demo', '--retrigger', 999, success=False)
    invoke('--demo', '--click-unit', 'invalid', success=False)
    invoke('--demo', '--unknown', 2, success=False)
    demo = invoke('--demo')
    assert demo['detectedClicks'] == 16 and demo['noteMilliseconds']['1/32'] == 62.5
print(f'CLI integration passed: {checks} invocations; PCM16/24/32, float32, channel 64, independent channel tempos, quiet clicks, silence, tempo changes and errors.')
