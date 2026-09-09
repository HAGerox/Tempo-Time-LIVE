#!/usr/bin/env python3
"""Exercise the actual bundled-audio protocol, including the real 30-second timeout."""
import json
import queue
import subprocess
import sys
import threading
import time

process = subprocess.Popen([sys.argv[1], '--demo'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
updates = queue.Queue()
def read():
    for line in process.stdout:
        updates.put(json.loads(line))
threading.Thread(target=read, daemon=True).start()
def send(action, **extra):
    process.stdin.write(json.dumps(dict(action=action, **extra)) + '\n')
    process.stdin.flush()
def until(predicate, timeout=7):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = updates.get(timeout=max(.01, deadline - time.monotonic()))
        if predicate(value):
            return value
    raise AssertionError('Timed out waiting for audio service')
try:
    first = until(lambda s: 'devices' in s)
    signal = until(lambda s: s['listening'] and s['peakDB'] > -60)
    assert -60 < signal['peakDB'] <= 0
    audio = until(lambda s: s['pulse'] is not None)
    assert abs(audio['pulse'] - 500) < .1 and not audio['manual']
    send('tap')
    first_tap = until(lambda s: s['manual'])
    assert first_tap['pulse'] is None and first_tap['listening']
    time.sleep(.75)
    send('tap')
    manual = until(lambda s: s['manual'] and s['pulse'] is not None)
    assert 650 < manual['pulse'] < 900, manual
    print('Audio 120 BPM; first tap clears audio value; taps override while capture continues.', flush=True)
    restored = until(lambda s: not s['manual'], timeout=33)
    assert abs(restored['pulse'] - 500) < .1 and restored['listening']
    send('select', channel=1)
    changing = until(lambda s: s['starting'])
    assert changing['pulse'] is None and changing['peakDB'] == -120
    restarted = until(lambda s: s['listening'] and s['pulse'] is not None)
    assert abs(restarted['pulse'] - 500) < .1
    print('Automatic capture on launch, live meter, 30-second return, and automatic capture after channel selection passed.', flush=True)
finally:
    process.stdin.close()
    process.wait(timeout=5)
