import React, { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { invoke } from '@tauri-apps/api/core';
import './styles.css';
import { BeatPulseClock } from './beatPulseClock';

interface Device { uid: string; name: string; channels: number }
type DetectionMode = 'music' | 'click';
interface Snapshot {
  devices: Device[]; uid: string; channel: number; listening: boolean; starting: boolean;
  manual: boolean; mode: DetectionMode; status: string; bpm: number | null; pulse: number | null; error: string | null;
  peakDB: number; clipped?: boolean; beatSequence?: number; beatActive?: boolean; beatTime?: number | null;
}
const initial: Snapshot = { devices: [], uid: '', channel: 1, listening: false, starting: false, manual: false, mode: 'music', status: 'Connecting', bpm: null, pulse: null, error: null, peakDB: -120 };
const notes = [ [1, 'Whole'], [2, 'Half'], [4, 'Quarter'], [8, 'Eighth'], [16, 'Sixteenth'], [32, 'Thirty-second'] ] as const;

function Note({ value }: { value: number }) {
  const flags = value === 8 ? 1 : value === 16 ? 2 : value === 32 ? 3 : 0;
  return <svg viewBox="0 0 32 40" className="note" aria-hidden="true">
    <ellipse cx="10" cy="30" rx="7" ry="4.5" transform="rotate(-18 10 30)" fill={value > 2 ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth="2" />
    {value > 1 && <path d="M16 29V5" fill="none" stroke="currentColor" strokeWidth="2" />}
    {Array.from({ length: flags }, (_, i) => <path key={i} d={`M16 ${6 + i * 6} C17 ${12 + i * 6}, 28 ${10 + i * 6}, 24 ${19 + i * 6}`} fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />)}
  </svg>;
}

function App() {
  const [state, setState] = useState(initial);
  const [error, setError] = useState<string | null>(null);
  const [flash, setFlash] = useState(false);
  const flashTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const mounted = useRef(true);
  const lastBeat = useRef<number | undefined>(undefined);
  const beatClock = useRef(new BeatPulseClock());
  const beatSource = useRef('');
  const [songFlash, setSongFlash] = useState(false);
  const songTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const command = async (action: string, extra = {}) => {
    try { await invoke('audio_command', { action, ...extra }); setError(null); }
    catch (error) { setError(String(error)); }
  };
  const tap = () => {
    beatClock.current.reset();
    clearTimeout(songTimer.current); setSongFlash(false);
    setFlash(true);
    clearTimeout(flashTimer.current);
    flashTimer.current = setTimeout(() => setFlash(false), 100);
    void command('tap');
  };
  useEffect(() => {
    mounted.current = true;
    let timer: ReturnType<typeof setTimeout>;
    const poll = async () => {
      try { const next = await invoke<Snapshot>('snapshot'); if (mounted.current) setState(next); }
      catch (error) { if (mounted.current) setError(String(error)); }
      if (mounted.current) timer = setTimeout(poll, 33);
    };
    void poll();
    return () => { mounted.current = false; clearTimeout(timer); clearTimeout(flashTimer.current); };
  }, []);
  useEffect(() => {
    const source = `${state.uid}:${state.channel}:${state.mode}`;
    if (beatSource.current !== source) {
      beatSource.current = source;
      beatClock.current.reset();
      lastBeat.current = undefined;
      clearTimeout(songTimer.current); setSongFlash(false);
    }
    const fresh = state.beatSequence !== lastBeat.current;
    lastBeat.current = state.beatSequence;
    if (state.manual || !state.listening || state.starting || state.error || error || state.pulse == null) {
      beatClock.current.reset();
      clearTimeout(songTimer.current); setSongFlash(false);
      return;
    }
    const now = performance.now();
    const beatAt = state.beatTime != null ? now - (Date.now() - state.beatTime) : null;
    beatClock.current.update(state.pulse, now, fresh ? beatAt : null,
      beatAt == null ? now : beatAt + state.pulse * 3 + 80);
  }, [state.beatSequence, state.beatTime, state.beatActive, state.manual, state.listening, state.starting,
      state.error, state.pulse, state.uid, state.channel, state.mode, error]);
  useEffect(() => {
    let frame: number;
    const animate = (now: number) => {
      if (beatClock.current.tick(now)) {
        clearTimeout(songTimer.current); setSongFlash(true);
        songTimer.current = setTimeout(() => setSongFlash(false), 60);
      }
      frame = requestAnimationFrame(animate);
    };
    frame = requestAnimationFrame(animate);
    return () => { cancelAnimationFrame(frame); clearTimeout(songTimer.current); };
  }, []);
  useEffect(() => {
    const key = (event: KeyboardEvent) => {
      if (event.code !== 'Space' || event.repeat || event.metaKey || event.ctrlKey || event.altKey) return;
      const tag = (event.target as HTMLElement)?.tagName;
      if (['SELECT', 'INPUT', 'TEXTAREA', 'BUTTON'].includes(tag)) return;
      event.preventDefault(); tap();
    };
    window.addEventListener('keydown', key);
    return () => window.removeEventListener('keydown', key);
  }, []);
  const device = state.devices.find(device => device.uid === state.uid);
  const peakDB = state.listening && Number.isFinite(state.peakDB) ? Math.max(-60, Math.min(0, state.peakDB)) : -60;
  return <main>
    <section className="tempo-panel" aria-label="Tempo">
      <div className="routing">
        <label><span>Input</span><div className="select-wrap"><select aria-label="Audio input" value={state.uid} onChange={event => void command('select', { uid: event.target.value })}>
          {!device && <option value={state.uid}>{state.uid ? 'Input unavailable' : 'Choose input'}</option>}
          {state.devices.map(device => <option key={device.uid} value={device.uid}>{device.name}</option>)}
        </select></div></label>
        <div className="channel-line">
          <label><span>Channel</span><div className="select-wrap"><select aria-label="Input channel" disabled={!device} value={state.channel} onChange={event => void command('select', { channel: Number(event.target.value) })}>
            {Array.from({ length: device?.channels || 1 }, (_, i) => <option key={i + 1} value={i + 1}>{i + 1}</option>)}
          </select></div></label>
          <div className="level-meter" role="meter" aria-label={`Channel ${state.channel} input level`} aria-valuemin={-60} aria-valuemax={0} aria-valuenow={peakDB} aria-valuetext={state.listening ? `${Math.round(peakDB)} dBFS` : 'Waiting for audio'}>
            <span style={{ transform: `scaleX(${(peakDB + 60) / 60})`, background: state.clipped ? 'var(--coral)' : peakDB >= -12 ? '#d19a3c' : '#4f9870' }} />
          </div>
        </div>
      </div>
      <div className="dial-area">
        <button className={`dial ${flash ? 'tapped' : ''} ${songFlash ? 'song-beat' : ''}`} aria-label="Tap tempo" onPointerDown={event => { if (event.button === 0) { event.preventDefault(); event.currentTarget.focus(); tap(); } }} onClick={event => { if (event.detail === 0) tap(); }}>
          <span className="beat-indicator" aria-hidden="true" />
          <span className="bpm">{state.bpm == null ? '—' : Math.round(state.bpm)}</span>
          <span className="bpm-label">BPM</span>
          <span className="tap-label" role="status">{state.manual ? 'MANUAL' : 'TAP'}</span>
        </button>
        <div className="source-switch" role="group" aria-label="Incoming audio">
          {([['music', 'Music'], ['click', 'Click track']] as const).map(([mode, label]) =>
            <button key={mode} aria-pressed={state.mode === mode} onClick={() => void command('mode', { mode })}>{label}</button>
          )}
        </div>
      </div>
      <p className="error" role="alert">{error || state.error || ''}</p>
    </section>
    <section className="notes-panel" aria-label="Note lengths">
      <div className="notes-heading"><span>NOTE LENGTHS</span><span>MILLISECONDS</span></div>
      <dl>{notes.map(([denominator, name]) => <div className="note-row" key={denominator}>
        <dt><Note value={denominator} /><span>{name}</span></dt>
        <dd>{state.pulse == null ? '—' : Math.round(state.pulse * 4 / denominator)}<span className="unit"> ms</span></dd>
      </div>)}</dl>
    </section>
  </main>;
}

createRoot(document.getElementById('root')!).render(<App />);
