// Original music bed for the Thermal Map film, synthesized from scratch (no samples, no loops).
//   node Tools/demo/music.mjs [film/public/timeline.json] [out.wav]
// Calm D major pad with a soft arpeggio; light chimes where the film draws on a part, five ticks for the
// five solver passes, a lift with a gentle pulse at "under load", and a resolving chord on the end card.
// Writes 48 kHz stereo 32-bit float WAV. Cue times come from the narration timeline.
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const tlPath = process.argv[2] ?? join(here, "../../film/public/timeline.json");
const outPath = process.argv[3] ?? join(here, "../../film/public/music.wav");
const tl = JSON.parse(readFileSync(tlPath, "utf8"));
const at = (i) => tl.words[i].t0;

const SR = 48000;
const DUR = tl.total + 0.4;
const N = Math.ceil(DUR * SR);
const L = new Float32Array(N), R = new Float32Array(N);

// ---- cues (film seconds) ----
const CUE = {
  parts: [at(38) - 0.15, at(40) - 0.15, at(43) - 0.15], // the chip, the heat sink, the battery
  ripple: at(14) - 0.1, // "two hundred and five sensors"
  five: at(52) - 0.05, // five solver passes, 0.2 s apart
  load: at(68) - 0.1, // "Put it under load"
  spread: at(79) - 0.25,
  hide: at(85) - 0.1,
  predict: at(92) - 0.1,
  outside: at(98) - 0.2,
  end: at(109) - 0.3,
};

// ---- helpers ----
const mtof = (m) => 440 * Math.pow(2, (m - 69) / 12);
const TAB = 4096;
const SIN = new Float32Array(TAB + 1);
for (let i = 0; i <= TAB; i++) SIN[i] = Math.sin((2 * Math.PI * i) / TAB);
const sinP = (phase) => { // phase in cycles
  const p = (phase - Math.floor(phase)) * TAB;
  const i = p | 0, f = p - i;
  return SIN[i] + (SIN[i + 1] - SIN[i]) * f;
};
const smooth = (x) => (x <= 0 ? 0 : x >= 1 ? 1 : x * x * (3 - 2 * x));
function add(i, l, r) { if (i >= 0 && i < N) { L[i] += l; R[i] += r; } }

// ---- harmony: [start time, MIDI notes] ----
// D: Dmaj9 -> Bm9 -> Gmaj9(#11) -> Asus2/D ... lift on Em9 -> A(add9) under load, back home on Dmaj9.
const D9 = [50, 57, 61, 64, 66], Bm9 = [47, 54, 57, 61, 62], G9 = [43, 50, 54, 57, 61], A2 = [45, 52, 57, 59, 64];
const Em9 = [40, 47, 54, 55, 62], Aadd9 = [45, 52, 59, 61, 64], Dhome = [38, 50, 57, 61, 64, 66, 69];
const CHORDS = [
  [0, D9],
  [CUE.ripple + 1.6, Bm9],
  [CUE.parts[0] - 0.4, G9],
  [CUE.five - 1.0, A2],
  [CUE.load - 4.2, Bm9],
  [CUE.load, Em9],
  [CUE.spread - 0.2, Aadd9],
  [CUE.hide - 0.3, G9],
  [CUE.outside, A2],
  [CUE.end, Dhome],
];
const chordAt = (t) => { let c = CHORDS[0][1]; for (const [s, n] of CHORDS) if (t >= s) c = n; return c; };

// intensity envelope: calm, a light lift under load, settle, resolve
function energy(t) {
  let e = 0.35 + 0.15 * smooth((t - 1.5) / 6);
  e += 0.45 * smooth((t - (CUE.load - 1.2)) / 1.8) * (1 - smooth((t - CUE.outside) / 2.5));
  e += 0.15 * smooth((t - CUE.end) / 1.0);
  return e;
}

// ---- pad: additive, detuned, slow attack; chords crossfade ----
{
  const ATT = 1.4, REL = 1.8;
  CHORDS.forEach(([start, notes], ci) => {
    const end = ci + 1 < CHORDS.length ? CHORDS[ci + 1][0] : DUR;
    const s0 = Math.floor(start * SR), s1 = Math.min(N, Math.floor((end + REL) * SR));
    notes.forEach((m, ni) => {
      const f = mtof(m + 12 * (m < 45 ? 1 : 0));
      const voices = [-0.07, 0, 0.07].map((cents) => f * Math.pow(2, cents / 12));
      const pan = ((ni % 2) ? 0.35 : -0.35) * (ni / notes.length);
      const gain = 0.022 / Math.sqrt(notes.length);
      for (let i = s0; i < s1; i++) {
        const t = i / SR;
        const a = smooth((t - start) / ATT) * (t > end ? 1 - smooth((t - end) / REL) : 1);
        if (a <= 0) continue;
        const bright = 0.35 + 0.5 * energy(t);
        const slow = 1 + 0.12 * Math.sin(2 * Math.PI * 0.11 * t + ni);
        let v = 0;
        for (let k = 0; k < 3; k++) {
          const ph = voices[k] * t;
          v += sinP(ph) + 0.42 * bright * sinP(2 * ph + 0.1) + 0.2 * bright * bright * sinP(3 * ph + 0.3) + 0.08 * bright ** 3 * sinP(4 * ph);
        }
        v *= gain * a * slow;
        add(i, v * (1 - pan), v * (1 + pan));
      }
    });
  });
}

// ---- bass: soft sine root, follows the chord with a short glide (phase accumulated, so no clicks) ----
{
  let ph = 0, f = mtof(38);
  for (let i = 0; i < N; i++) {
    const t = i / SR;
    const root = chordAt(t)[0];
    const target = mtof(root < 45 ? root : root - 12);
    f += (target - f) * 0.0006;
    ph += f / SR;
    const a = 0.05 * smooth(t / 2.5) * (0.6 + 0.5 * energy(t)) * (1 - smooth((t - (DUR - 2.2)) / 2.2));
    const v = a * (sinP(ph) + 0.15 * sinP(2 * ph));
    add(i, v, v);
  }
}

// ---- plucks (arp, chimes, ticks) ----
function pluck(t0, midi, amp, decay, pan = 0, bell = 0) {
  const f = mtof(midi);
  const s0 = Math.floor(t0 * SR), len = Math.floor(Math.min(decay * 6, 4) * SR);
  for (let j = 0; j < len; j++) {
    const tt = j / SR;
    const env = Math.min(1, tt / 0.004) * Math.exp(-tt / decay);
    let v = sinP(f * tt) + 0.25 * sinP(2 * f * tt) * Math.exp(-tt / (decay * 0.4));
    if (bell) v += bell * sinP(2.76 * f * tt) * Math.exp(-tt / (decay * 0.5)) + 0.5 * bell * sinP(5.4 * f * tt) * Math.exp(-tt / (decay * 0.25));
    v *= amp * env;
    add(s0 + j, v * (1 - pan), v * (1 + pan));
  }
}
// arpeggio: eighths at 100 bpm, sixteenths during the lift; fades in after the opening line
{
  const beat = 60 / 100;
  const startArp = CUE.ripple - 0.3;
  let k = 0;
  for (let t = startArp; t < CUE.end + 0.2; k++) {
    const e = energy(t);
    const lifted = t > CUE.load - 0.3 && t < CUE.outside;
    const step = lifted ? beat / 4 : beat / 2;
    const notes = chordAt(t).filter((m) => m >= 50);
    const pattern = [0, 2, 1, 3, 2, 4, 1, 3];
    const m = notes[pattern[k % pattern.length] % notes.length] + 12;
    const amp = (lifted ? 0.03 : 0.024) * smooth((t - startArp) / 2.5) * (0.6 + 0.6 * e);
    pluck(t, m, amp, lifted ? 0.18 : 0.32, (k % 2 ? 0.4 : -0.4));
    t += step;
  }
}
// chimes where a part is outlined, and on the hide/predict moments
CUE.parts.forEach((t, i) => pluck(t, [81, 78, 76][i], 0.05, 0.9, [-0.3, 0.3, 0][i], 0.5));
pluck(CUE.hide, 74, 0.035, 0.6, -0.2, 0.4);
pluck(CUE.predict, 81, 0.045, 1.1, 0.2, 0.5);
pluck(CUE.ripple, 86, 0.03, 1.4, 0, 0.6);
// five ticks for the five solver passes
for (let i = 0; i < 5; i++) pluck(CUE.five + i * 0.2, 93, 0.02, 0.05, i % 2 ? 0.5 : -0.5, 0.2);
// resolving bloom on the end card
[62, 69, 73, 76, 81].forEach((m, i) => pluck(CUE.end + 0.05 + i * 0.07, m, 0.03, 2.2, (i - 2) * 0.2, 0.35));

// ---- the lift: a soft pulse under load and a quiet noise swell into it ----
{
  const beat = 60 / 100;
  for (let t = CUE.load; t < CUE.outside - 0.2; t += beat) {
    const s0 = Math.floor(t * SR), len = Math.floor(0.32 * SR);
    const amp = 0.11 * smooth((t - CUE.load) / 1.2) * (1 - smooth((t - (CUE.outside - 2.4)) / 2.2));
    let ph = 0;
    for (let j = 0; j < len; j++) {
      const tt = j / SR;
      ph += (48 + 50 * Math.exp(-tt / 0.03)) / SR;
      const v = amp * sinP(ph) * Math.exp(-tt / 0.09) * Math.min(1, tt / 0.003);
      add(s0 + j, v, v);
    }
  }
  // noise swell, gently low-passed
  let seed = 12345, lpL = 0, lpR = 0;
  const rnd = () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296 * 2 - 1; };
  const a0 = CUE.load - 2.2, a1 = CUE.load + 0.2;
  for (let i = Math.floor(a0 * SR); i < Math.floor((a1 + 0.6) * SR); i++) {
    const t = i / SR;
    const env = t < a1 ? smooth((t - a0) / (a1 - a0)) ** 2 : 1 - smooth((t - a1) / 0.6);
    const c = 0.006 + 0.06 * smooth((t - a0) / (a1 - a0));
    lpL += c * (rnd() - lpL); lpR += c * (rnd() - lpR);
    add(i, 0.09 * env * lpL, 0.09 * env * lpR);
  }
}

// ---- reverb: Schroeder/Freeverb style, 6 combs + 2 allpasses per side ----
function reverb(x, combs, aps, fb = 0.84, damp = 0.25) {
  const out = new Float32Array(x.length);
  for (const d of combs) {
    const buf = new Float32Array(d); let idx = 0, lp = 0;
    for (let i = 0; i < x.length; i++) {
      const y = buf[idx];
      lp = y * (1 - damp) + lp * damp;
      buf[idx] = x[i] + lp * fb;
      out[i] += y / combs.length;
      idx = (idx + 1) % d;
    }
  }
  for (const d of aps) {
    const buf = new Float32Array(d); let idx = 0;
    for (let i = 0; i < out.length; i++) {
      const b = buf[idx];
      const y = -out[i] + b;
      buf[idx] = out[i] + b * 0.5;
      out[i] = y;
      idx = (idx + 1) % d;
    }
  }
  return out;
}
const sc = SR / 44100;
const wl = reverb(L, [1557, 1617, 1491, 1422, 1277, 1356].map((d) => Math.round(d * sc * 1.6)), [556, 441].map((d) => Math.round(d * sc)));
const wr = reverb(R, [1580, 1640, 1514, 1445, 1300, 1379].map((d) => Math.round(d * sc * 1.6)), [579, 464].map((d) => Math.round(d * sc)));

// ---- mix, gentle fade in/out, normalise peak to -6 dBFS (the final mix sets loudness) ----
let peak = 0;
for (let i = 0; i < N; i++) {
  const t = i / SR;
  const g = smooth(t / 0.8) * (1 - smooth((t - (DUR - 1.6)) / 1.6));
  L[i] = (L[i] * 0.72 + wl[i] * 0.55) * g;
  R[i] = (R[i] * 0.72 + wr[i] * 0.55) * g;
  peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i]));
}
const norm = 0.5 / peak;

// ---- write float WAV ----
const data = Buffer.alloc(N * 2 * 4);
for (let i = 0; i < N; i++) { data.writeFloatLE(L[i] * norm, i * 8); data.writeFloatLE(R[i] * norm, i * 8 + 4); }
const h = Buffer.alloc(44);
h.write("RIFF", 0); h.writeUInt32LE(36 + data.length, 4); h.write("WAVE", 8);
h.write("fmt ", 12); h.writeUInt32LE(16, 16); h.writeUInt16LE(3, 20); h.writeUInt16LE(2, 22);
h.writeUInt32LE(SR, 24); h.writeUInt32LE(SR * 8, 28); h.writeUInt16LE(8, 32); h.writeUInt16LE(32, 34);
h.write("data", 36); h.writeUInt32LE(data.length, 40);
writeFileSync(outPath, Buffer.concat([h, data]));
console.log(`music: ${DUR.toFixed(2)} s, cues ${JSON.stringify(Object.fromEntries(Object.entries(CUE).map(([k, v]) => [k, Array.isArray(v) ? v.map((x) => +x.toFixed(2)) : +v.toFixed(2)])))}`);
