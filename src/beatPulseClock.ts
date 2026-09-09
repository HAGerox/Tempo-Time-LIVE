/** Monotonic visual beat clock. Detection nudges phase; tempo sets cadence. */
export class BeatPulseClock {
  private period = 0;
  private next: number | null = null;
  private last = -Infinity;
  private expires = Infinity;

  reset() { this.period = 0; this.next = null; this.last = -Infinity; this.expires = Infinity; }

  update(period: number, now: number, detectedAt: number | null, expires = Infinity) {
    this.expires = expires;
    if (!Number.isFinite(period) || period < 100 || period > 3000) {
      this.reset(); return;
    }
    if (this.next !== null && this.period !== period) {
      // Keep our position within the beat when the tempo estimate changes.
      this.next = now + Math.max(0, Math.min(1, (this.next - now) / this.period)) * period;
    }
    this.period = period;
    if (detectedAt === null || !Number.isFinite(detectedAt)) return;
    if (this.next === null) {
      this.next = detectedAt + Math.max(0, Math.ceil((now - detectedAt) / period)) * period;
      return;
    }
    const nearest = this.next + Math.round((detectedAt - this.next) / period) * period;
    const error = detectedAt - nearest;
    // The song tracker has already rejected unsupported beats. Follow accepted
    // musical timing promptly; only a newly established lock can jump phase.
    this.next += Math.abs(error) > period * 0.3 ? error : error * 0.65;
    if (this.next < now) this.next += Math.ceil((now - this.next) / period) * period;
  }

  tick(now: number): boolean {
    if (now > this.expires) { this.reset(); return false; }
    if (this.next === null || now < this.next) return false;
    const late = now - this.next;
    this.next += (Math.floor(late / this.period) + 1) * this.period;
    // No burst of missed flashes after the window was suspended.
    if (late > Math.min(100, this.period * 0.25) || now - this.last < this.period * 0.5) return false;
    this.last = now;
    return true;
  }
}
