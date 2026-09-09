import assert from 'node:assert/strict';
import { test } from 'node:test';
import { BeatPulseClock } from '../.build/pulse-tests/beatPulseClock.js';

test('tempo drives beats through missing detections', () => {
  const clock = new BeatPulseClock();
  clock.update(500, 0, null);
  assert.equal(clock.tick(0), false);
  clock.update(500, 100, 100);
  assert.equal(clock.tick(100), true);
  for (const time of [600, 1100, 1600, 2100]) {
    assert.equal(clock.tick(time - 1), false);
    assert.equal(clock.tick(time), true);
    assert.equal(clock.tick(time), false);
  }
});
test('trusted musical timing corrects phase promptly without extra flashes', () => {
  const clock = new BeatPulseClock();
  clock.update(500, 0, 0); assert.ok(clock.tick(0));
  clock.update(500, 480, 480);
  assert.equal(clock.tick(480), false);
  assert.equal(clock.tick(487), true);
  clock.update(500, 530, 500);
  assert.equal(clock.tick(530), false);
});
test('tempo changes preserve beat position; reset stops pulses', () => {
  const clock = new BeatPulseClock();
  clock.update(500, 0, 0); clock.tick(0);
  clock.update(400, 250, null);
  assert.equal(clock.tick(449), false); assert.ok(clock.tick(450));
  assert.ok(clock.tick(850));
  clock.reset(); assert.equal(clock.tick(1250), false);
  clock.update(400, 1300, null); assert.equal(clock.tick(1300), false);
  clock.update(400, 1400, 1400); assert.ok(clock.tick(1400));
});
test('suspension skips old pulses without a catch-up burst', () => {
  const clock = new BeatPulseClock();
  clock.update(500, 0, 0); clock.tick(0);
  assert.equal(clock.tick(2750), false);
  assert.equal(clock.tick(2751), false);
  assert.ok(clock.tick(3000));
});

test('late detection delivery preserves the original audio phase', () => {
  const clock = new BeatPulseClock();
  clock.update(500, 180, 0);
  assert.equal(clock.tick(180), false);
  assert.equal(clock.tick(499), false);
  assert.ok(clock.tick(500));
  clock.update(500, 720, 500);
  assert.equal(clock.tick(999), false);
  assert.ok(clock.tick(1000));
});
test('a newly accepted offset lock recovers phase without double flashes', () => {
  const clock = new BeatPulseClock();
  clock.update(500, 0, 0); clock.tick(0);
  for (const t of [220, 720, 1220]) {
    clock.update(500, t + 100, t);
    clock.tick(t + 100);
  }
  assert.equal(clock.tick(1719), false);
  assert.ok(clock.tick(1720));
});

test('expired evidence stops flashes even if service updates stall', () => {
  const clock = new BeatPulseClock();
  clock.update(500, 100, 0, 1580);
  assert.ok(clock.tick(500));
  assert.ok(clock.tick(1000));
  assert.ok(clock.tick(1500));
  assert.equal(clock.tick(2000), false);
  clock.update(500, 2100, null, 3000);
  assert.equal(clock.tick(2500), false);
});

test('60 Hz display follows a musical grid despite delayed, quantized and missing detections', () => {
  const clock = new BeatPulseClock();
  const period = 60000 / 136;
  let detection = 0;
  const errors = [];
  for (let frame = 0; frame < 1200; frame++) {
    const now = frame * 1000 / 60;
    if (now >= detection * period + 120) {
      // Miss every seventh detection; successful events arrive 120 ms late.
      if (detection % 7 !== 6) {
        const at = Math.round(detection * period / 20) * 20;
        clock.update(period, now, at, at + period * 3 + 80);
      }
      detection++;
    }
    if (clock.tick(now)) errors.push(Math.abs(now - Math.round(now / period) * period));
  }
  assert.ok(errors.length >= 43, `Only ${errors.length} flashes`);
  assert.ok(Math.max(...errors) < 35, `Worst phase error ${Math.max(...errors)} ms`);
});
