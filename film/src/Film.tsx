import React from "react";
import {
  AbsoluteFill,
  Audio,
  Easing,
  OffthreadVideo,
  Sequence,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import timeline from "../public/timeline.json";
import sensorsJson from "../public/sensors.json";

// Thermal Map demo, v2. Real headless footage, eased camera moves, hairline annotations drawn on the
// parts as the narrator names them, and our own synthesized music bed (mixed in afterwards, see
// Tools/demo/mix.sh). Times are film seconds; word times come from timeline.json (scripts/timeline.mjs).

export const FPS = 30;
export const DURATION_S: number = timeline.total;

const SW = 2458;
const SH = 1382;
const BG = "#0d0d10";
const ICE = "#A1D1FF";
const FONT = '"SF Pro Display", -apple-system, BlinkMacSystemFont, system-ui, sans-serif';
const TEXT = '"SF Pro Text", -apple-system, BlinkMacSystemFont, system-ui, sans-serif';

// ---------- board geometry: millimetres (top view) to source pixels of the recorded frame ----------
// Measured on the footage (film/scripts/measure.mjs): the 304.1 x 215 mm shell spans x 224.5-1668.5 px,
// y 178.5-1199.4 px; the bottom view is mirrored left to right.
const MM = 4.748;
const OX = 224.5;
const OY = 178.5;
const BW = 304.1;
const px = (x: number, y: number) => ({ x: OX + (BW - x) * MM, y: OY + y * MM });
const rectPx = (x: number, y: number, w: number, h: number) => ({ x: OX + (BW - x - w) * MM, y: OY + y * MM, w: w * MM, h: h * MM });

const PART = {
  m3: [185.9, 22.1, 43.8, 39.2],
  sink: [190.8, 14, 97.4, 54],
  cells: [
    [13.5, 75.7, 131.6, 46.9],
    [158.1, 75.7, 133.0, 46.9],
    [9.2, 125.2, 75.6, 67.9],
    [218.8, 125.2, 74.2, 67.9],
  ],
} as const;
const DIE = { x: 207.8, y: 41.6 };
const SENSORS = (sensorsJson as { key: string; x: number; y: number; die: boolean }[]).filter((s) => !s.die);
const HIDDEN = ["Th08", "Th09", "Th0A"].map((k) => SENSORS.find((s) => s.key === k)!);

// ---------- timing helpers ----------
const W = timeline.words as { text: string; t0: number; t1: number }[];
const at = (i: number) => W[i].t0;
const ease = Easing.bezier(0.45, 0, 0.2, 1);
const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const ramp = (t: number, a: number, b: number) => interpolate(t, [a, b], [0, 1], { ...clamp, easing: ease });
/** 0 -> 1 -> 0 envelope: in over [a, a+fin], out over [b-fout, b] */
const env = (t: number, a: number, b: number, fin = 0.35, fout = 0.45) =>
  Math.min(interpolate(t, [a, a + fin], [0, 1], clamp), interpolate(t, [b - fout, b], [1, 0], clamp));

// ---------- camera ----------
// A key: centre in board mm (top view) or `frame` fractions, and vw = visible width as a fraction of the frame.
type Key = { t: number; cx: number; cy: number; vw: number };
const kmm = (t: number, x: number, y: number, vw: number): Key => {
  const p = px(x, y);
  return { t, cx: p.x / SW, cy: p.y / SH, vw };
};
const kf = (t: number, cx: number, cy: number, vw: number): Key => ({ t, cx, cy, vw });

function camAt(keys: Key[], t: number): Key {
  if (t <= keys[0].t) return keys[0];
  for (let i = 0; i < keys.length - 1; i++) {
    const a = keys[i], b = keys[i + 1];
    if (t <= b.t) {
      const p = ease((t - a.t) / (b.t - a.t));
      return { t, cx: a.cx + (b.cx - a.cx) * p, cy: a.cy + (b.cy - a.cy) * p, vw: a.vw * Math.pow(b.vw / a.vw, p) };
    }
  }
  return keys[keys.length - 1];
}

// ---------- drawing primitives (source-pixel space; `s` = current camera scale) ----------
const glow = (s: number, a = 0.75) => `drop-shadow(0 0 ${5 / s}px rgba(161,209,255,${a}))`;

const DrawRect: React.FC<{ r: { x: number; y: number; w: number; h: number }; p: number; o: number; s: number; radius?: number; pad?: number }> = ({
  r, p, o, s, radius = 10, pad = 6,
}) => (
  <rect
    x={r.x - pad} y={r.y - pad} width={r.w + 2 * pad} height={r.h + 2 * pad} rx={radius} ry={radius}
    pathLength={1} strokeDasharray={1} strokeDashoffset={1 - p}
    fill="none" stroke={ICE} strokeWidth={1.6 / s} opacity={o} style={{ filter: glow(s) }}
  />
);

const DrawCircle: React.FC<{ c: { x: number; y: number }; rad: number; p: number; o: number; s: number; dash?: boolean; width?: number }> = ({
  c, rad, p, o, s, dash, width = 1.6,
}) => (
  <circle
    cx={c.x} cy={c.y} r={rad} transform={`rotate(-90 ${c.x} ${c.y})`}
    pathLength={1} strokeDasharray={dash ? `${0.04} ${0.025}` : 1} strokeDashoffset={dash ? 0 : 1 - p}
    fill="none" stroke={ICE} strokeWidth={width / s} opacity={o * (dash ? p : 1)} style={{ filter: glow(s) }}
  />
);

/** Small label pill anchored at a source-pixel point (bottom edge at the point); size stays constant on screen. */
const Tag: React.FC<{ at: { x: number; y: number }; text: string; o: number; s: number; align?: "left" | "center" | "right"; size?: number }> = ({
  at: p, text, o, s, align = "left", size = 22,
}) => {
  const shift = align === "left" ? "0%" : align === "center" ? "-50%" : "-100%";
  return (
    <div style={{ position: "absolute", left: p.x, top: p.y, width: 0, height: 0, transform: `scale(${1 / s})`, transformOrigin: "0 0" }}>
      <div
        style={{
          position: "absolute", left: 0, top: 0, opacity: o,
          transform: `translate(${shift}, -100%) translateY(${(1 - o) * 6}px)`,
          whiteSpace: "nowrap", fontFamily: TEXT, fontSize: size, fontWeight: 600, letterSpacing: 0.1, color: "#fff",
          padding: "5px 11px", borderRadius: 999, background: "rgba(12,14,20,0.62)",
          border: "1px solid rgba(161,209,255,0.45)", boxShadow: "0 0 14px rgba(161,209,255,0.25)",
        }}
      >
        {text}
      </div>
    </div>
  );
};

/** Dashes flowing along a polyline: speed in source px per second, a fixed arrowhead at the end. */
const Flow: React.FC<{ pts: { x: number; y: number }[]; t: number; speed: number; o: number; s: number; head?: boolean }> = ({ pts, t, speed, o, s, head = true }) => {
  const d = pts.map((q, i) => `${i ? "L" : "M"}${q.x},${q.y}`).join(" ");
  const a = pts[pts.length - 2], b = pts[pts.length - 1];
  const ang = Math.atan2(b.y - a.y, b.x - a.x);
  const hl = 11 / s;
  const h1 = { x: b.x - hl * Math.cos(ang - 0.5), y: b.y - hl * Math.sin(ang - 0.5) };
  const h2 = { x: b.x - hl * Math.cos(ang + 0.5), y: b.y - hl * Math.sin(ang + 0.5) };
  return (
    <g opacity={o} style={{ filter: glow(s, 0.6) }}>
      <path d={d} fill="none" stroke={ICE} strokeWidth={2 / s} strokeLinecap="round" strokeDasharray={`${10 / s} ${12 / s}`} strokeDashoffset={-t * speed} />
      {head && <path d={`M${h1.x},${h1.y} L${b.x},${b.y} L${h2.x},${h2.y}`} fill="none" stroke={ICE} strokeWidth={2 / s} strokeLinecap="round" strokeLinejoin="round" />}
    </g>
  );
};

// ---------- the annotations, by section ----------
type Ctx = { t: number; s: number; tall: boolean };

const IdleMarks: React.FC<Ctx> = ({ t, s }) => {
  const els: React.ReactNode[] = [];
  const tags: React.ReactNode[] = [];
  // "the 13-inch MacBook Air with M3": the laptop's outline draws itself, with the model as a tag
  const mb = at(8) - 0.15;
  const mo = env(t, mb, at(13) + 0.2, 0.2, 0.5);
  if (mo > 0) {
    const shell = rectPx(0, 0, BW, 215);
    els.push(<DrawRect key="mb" r={shell} p={ramp(t, mb, mb + 1.2)} o={mo} s={s} radius={11 * MM + 10} pad={10} />);
    const p = px(152, 0);
    tags.push(<Tag key="tmb" at={{ x: p.x, y: p.y - 26 }} text="MacBook Air 13-inch · M3" o={mo} s={s} align="center" size={24} />);
  }
  // "205 sensors": a ripple through every sensor dot, spreading out from the die
  const r0 = at(14) - 0.1;
  if (t > r0 && t < r0 + 2.4) {
    const die = px(DIE.x, DIE.y);
    SENSORS.forEach((sn, i) => {
      const p = px(sn.x, sn.y);
      const dist = Math.hypot(p.x - die.x, p.y - die.y);
      const local = t - r0 - dist / 1500;
      if (local < 0 || local > 0.9) return;
      const k = local / 0.9;
      els.push(<circle key={`r${i}`} cx={p.x} cy={p.y} r={6 + 22 * k} fill="none" stroke={ICE} strokeWidth={1.5 / s} opacity={(1 - k) * 0.95} />);
      els.push(<circle key={`d${i}`} cx={p.x} cy={p.y} r={5.5} fill={ICE} opacity={(1 - k) * 0.85} />);
    });
    // the 80 die sensors flash as one
    const dk = interpolate(t, [r0, r0 + 0.25, r0 + 1.0], [0, 1, 0], clamp);
    const m3 = rectPx(PART.m3[0], PART.m3[1], PART.m3[2], PART.m3[3]);
    els.push(<rect key="die" x={m3.x} y={m3.y} width={m3.w} height={m3.h} rx={8} fill={ICE} opacity={dk * 0.16} />);
  }
  const sensorsTag = env(t, at(14), at(22) + 0.3, 0.35, 0.4);
  if (sensorsTag > 0) {
    const p = px(152, 0);
    tags.push(<Tag key="t205" at={{ x: p.x, y: p.y - 26 }} text="205 sensors" o={sensorsTag} s={s} align="center" size={24} />);
  }

  // the chip, the heat sink, the battery
  const chip = at(38) - 0.15, sink = at(41) - 0.15, bat = at(43) - 0.15, out = at(45) + 0.1;
  const m3 = rectPx(PART.m3[0], PART.m3[1], PART.m3[2], PART.m3[3]), hs = rectPx(PART.sink[0], PART.sink[1], PART.sink[2], PART.sink[3]);
  if (t > chip && t < out) {
    const o = env(t, chip, sink + 0.5, 0.15, 0.5);
    els.push(<DrawRect key="m3" r={m3} p={ramp(t, chip, chip + 0.55)} o={o} s={s} radius={12} />);
    tags.push(<Tag key="tm3" at={{ x: m3.x - 6, y: m3.y - 16 }} text="M3" o={o} s={s} />);
  }
  if (t > sink && t < out + 0.4) {
    const o = env(t, sink, bat + 0.6, 0.15, 0.5);
    els.push(<DrawRect key="hs" r={hs} p={ramp(t, sink, sink + 0.7)} o={o} s={s} radius={14} pad={8} />);
    tags.push(<Tag key="ths" at={{ x: hs.x - 8, y: hs.y - 18 }} text="Heat sink" o={o} s={s} />);
  }
  if (t > bat && t < out + 1.2) {
    const o = env(t, bat, out + 0.9, 0.15, 0.55);
    PART.cells.forEach((c, i) => {
      els.push(<DrawRect key={`c${i}`} r={rectPx(c[0], c[1], c[2], c[3])} p={ramp(t, bat + i * 0.09, bat + 0.55 + i * 0.09)} o={o} s={s} radius={12} pad={-3} />);
    });
    const c = px(152, 124);
    tags.push(<Tag key="tbat" at={{ x: c.x, y: c.y + 10 }} text="Battery" o={o} s={s} align="center" />);
  }

  // "solves the heat equation, five times a second": one slow pass, then five quick ones at 5 Hz
  const solve = at(48) - 0.1;
  const shell = rectPx(0, 0, BW, 215);
  const sweep = (k: number, key: string, a: number) => {
    const x = shell.x + shell.w * k;
    els.push(<rect key={key} x={x - 60} y={shell.y} width={60} height={shell.h} fill="url(#sweep)" opacity={a} />);
    els.push(<line key={key + "l"} x1={x} y1={shell.y} x2={x} y2={shell.y + shell.h} stroke={ICE} strokeWidth={1.6 / s} opacity={a} style={{ filter: glow(s) }} />);
  };
  if (t > solve && t < solve + 1.1) sweep(ease((t - solve) / 1.1), "sw", Math.sin(Math.PI * (t - solve) / 1.1));
  const five = at(52) - 0.05;
  for (let i = 0; i < 5; i++) {
    const a = five + i * 0.2;
    if (t > a && t < a + 0.2) sweep((t - a) / 0.2, `f${i}`, 0.75);
  }
  const eq = env(t, solve, at(56) - 0.1, 0.35, 0.4);
  if (eq > 0) {
    const p = px(152, 215);
    tags.push(<Tag key="eq" at={{ x: p.x, y: p.y + 58 }} text="∇ · (k ∇T) = 0" o={eq} s={s} align="center" size={25} />);
  }
  return (
    <>
      <svg width={SW} height={SH} style={{ position: "absolute", left: 0, top: 0, overflow: "visible" }}>
        <defs>
          <linearGradient id="sweep" x1="0" x2="1" y1="0" y2="0">
            <stop offset="0" stopColor={ICE} stopOpacity={0} />
            <stop offset="1" stopColor={ICE} stopOpacity={0.22} />
          </linearGradient>
        </defs>
        {els}
      </svg>
      {tags}
    </>
  );
};

const LoadMarks: React.FC<Ctx> = ({ t, s }) => {
  const els: React.ReactNode[] = [];
  const tags: React.ReactNode[] = [];
  // fast flow along the aluminium heat sink, from the die outward; slow creep into the battery
  const fastA = at(57) - 0.2, fastB = at(64) + 0.2;
  const fo = env(t, fastA, at(68) - 0.2, 0.4, 0.5);
  if (fo > 0) {
    for (const y of [26, 41.6, 57]) {
      els.push(<Flow key={`f${y}`} pts={[px(222, y), px(284, y)]} t={t} speed={260} o={fo} s={s} />);
    }
    const p = px(254, 14);
    tags.push(<Tag key="fast" at={{ x: p.x, y: p.y - 12 }} text="Aluminium · fast" o={fo} s={s} align="center" />);
  }
  const so = env(t, fastB, at(68) - 0.1, 0.4, 0.5);
  if (so > 0) {
    for (const x of [175, 205, 235]) {
      els.push(<Flow key={`s${x}`} pts={[px(x, 66), px(x, 92)]} t={t} speed={22} o={so} s={s} />);
    }
    const p = px(205, 96);
    tags.push(<Tag key="slow" at={{ x: p.x, y: p.y + 44 }} text="Battery · slow" o={so} s={s} align="center" />);
  }

  // under load: the M3 outlined, then rings spreading out with "spread"
  const lo = env(t, at(68) - 0.1, at(80) - 0.2, 0.35, 0.45);
  if (lo > 0) {
    const p = px(152, 0);
    tags.push(<Tag key="load" at={{ x: p.x, y: p.y - 26 }} text="Under load" o={lo} s={s} align="center" size={24} />);
  }
  const die = px(DIE.x, DIE.y);
  const m3t = at(75) - 0.15;
  if (t > m3t && t < at(80)) {
    const o = env(t, m3t, at(80), 0.12, 0.5);
    els.push(<DrawCircle key="m3c" c={die} rad={19 * MM} p={ramp(t, m3t, m3t + 0.6)} o={o} s={s} />);
  }
  const sp = at(79) - 0.25;
  for (let i = 0; i < 3; i++) {
    const a = sp + i * 0.28;
    if (t > a && t < a + 1.3) {
      const k = (t - a) / 1.3;
      els.push(<circle key={`sp${i}`} cx={die.x} cy={die.y} r={(19 + 46 * ease(k)) * MM} fill="none" stroke={ICE} strokeWidth={1.4 / s} opacity={(1 - k) * 0.8} />);
    }
  }

  // the held-out test: three heat-sink sensors hidden, then predicted
  const hide = at(85) - 0.1, pred = at(92) - 0.1, two = at(96) - 0.1, end = at(98) + 0.2;
  if (t > at(80) && t < end + 0.4) {
    const o = env(t, at(80), end + 0.3, 0.3, 0.5);
    HIDDEN.forEach((sn, i) => {
      const c = px(sn.x, sn.y);
      els.push(<DrawCircle key={`hc${i}`} c={c} rad={22} p={ramp(t, at(80) + i * 0.1, at(80) + 0.5 + i * 0.1)} o={o} s={s} dash={t > hide} width={1.4} />);
      const hidden = ramp(t, hide, hide + 0.35) * o;
      els.push(<circle key={`hd${i}`} cx={c.x} cy={c.y} r={11} fill={BG} opacity={hidden * 0.92} />);
      const pr = ramp(t, pred + i * 0.12, pred + 0.4 + i * 0.12) * o;
      const L = 15;
      els.push(
        <g key={`x${i}`} opacity={pr} style={{ filter: glow(s) }}>
          <line x1={c.x - L} y1={c.y} x2={c.x - 6} y2={c.y} stroke="#fff" strokeWidth={1.4 / s} />
          <line x1={c.x + 6} y1={c.y} x2={c.x + L} y2={c.y} stroke="#fff" strokeWidth={1.4 / s} />
          <line x1={c.x} y1={c.y - L} x2={c.x} y2={c.y - 6} stroke="#fff" strokeWidth={1.4 / s} />
          <line x1={c.x} y1={c.y + 6} x2={c.x} y2={c.y + L} stroke="#fff" strokeWidth={1.4 / s} />
          <circle cx={c.x} cy={c.y} r={3} fill={ICE} />
        </g>,
      );
    });
    const tagAt = px(HIDDEN[0].x - 10, HIDDEN[0].y - 6);
    const label = t < hide ? "Heat-sink sensors" : t < pred ? "Hidden from the model" : t < two ? "Predicted" : "Within 2 °C";
    tags.push(<Tag key="ho" at={{ x: tagAt.x + 40, y: tagAt.y - 12 }} text={label} o={o} s={s} />);
  }
  return (
    <>
      <svg width={SW} height={SH} style={{ position: "absolute", left: 0, top: 0, overflow: "visible" }}>{els}</svg>
      {tags}
    </>
  );
};

const CaseMarks: React.FC<Ctx> = ({ t, s }) => {
  const a = at(102) - 0.2;
  const o = env(t, a, at(109) + 0.1, 0.2, 0.6);
  if (o <= 0) return null;
  const shell = rectPx(0, 0, BW, 215);
  const p = px(152, 203);
  return (
    <>
      <svg width={SW} height={SH} style={{ position: "absolute", left: 0, top: 0, overflow: "visible" }}>
        <DrawRect r={shell} p={ramp(t, a, a + 1.1)} o={o} s={s} radius={11 * MM + 10} pad={10} />
      </svg>
      <Tag at={{ x: p.x, y: p.y }} text="Bottom case" o={o} s={s} align="center" size={24} />
    </>
  );
};

// ---------- a footage section: clip + camera + its annotations ----------
const Section: React.FC<{
  src: string; from: number; to: number; keys: Key[]; fadeIn: number; fadeOut?: number;
  Marks?: React.FC<Ctx>; tall: boolean;
}> = ({ src, from, to, keys, fadeIn, fadeOut = 0, Marks, tall }) => {
  const frame = useCurrentFrame();
  const { width, height } = useVideoConfig();
  const t = from + frame / FPS;
  const c = camAt(keys, t);
  const s = width / (c.vw * SW);
  const x = width / 2 - c.cx * SW * s;
  const y = height / 2 - c.cy * SH * s;
  let opacity = interpolate(t, [from, from + fadeIn], [0, 1], clamp);
  if (fadeOut) opacity *= interpolate(t, [to - fadeOut, to], [1, 0], clamp);
  return (
    <AbsoluteFill style={{ opacity }}>
      <div style={{ position: "absolute", left: 0, top: 0, width: SW, height: SH, transformOrigin: "0 0", transform: `translate(${x}px, ${y}px) scale(${s})` }}>
        <OffthreadVideo src={staticFile(src)} muted style={{ width: SW, height: SH }} />
        {Marks && <Marks t={t} s={s} tall={tall} />}
      </div>
    </AbsoluteFill>
  );
};

const Card: React.FC<{ len: number; end?: boolean }> = ({ len, end }) => {
  const frame = useCurrentFrame();
  const { width, height } = useVideoConfig();
  const t = frame / FPS;
  const u = Math.min(width, height) / 1080;
  const bg = end ? interpolate(t, [0, 0.7], [0, 1], clamp) : interpolate(t, [len - 0.5, len], [1, 0], clamp);
  const text = end ? interpolate(t, [0.4, 1.2], [0, 1], clamp) : interpolate(t, [0.05, 0.5, len - 0.6, len - 0.25], [0, 1, 1, 0], clamp);
  const fadeAll = end ? interpolate(t, [len - 0.6, len], [1, 0], clamp) : 1;
  const rise = interpolate(t, [end ? 0.4 : 0.05, end ? 1.6 : 1.0], [10, 0], { ...clamp, easing: ease });
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", fontFamily: FONT }}>
      <AbsoluteFill style={{ background: BG, opacity: bg }} />
      <div style={{ opacity: text * fadeAll, transform: `translateY(${rise * u}px)`, textAlign: "center" }}>
        <div style={{ fontSize: (end ? 92 : 104) * u, fontWeight: 600, color: "#fff", letterSpacing: -2.2 * u }}>Thermal Map</div>
        {end && (
          <>
            <div style={{ marginTop: 14 * u, fontSize: 26 * u, fontWeight: 500, color: "rgba(255,255,255,0.55)" }}>Made for MacBook Air 13-inch with M3</div>
            <div style={{ marginTop: 26 * u, fontSize: 34 * u, fontWeight: 400, color: "rgba(255,255,255,0.78)" }}>Free and open source.</div>
            <div style={{ marginTop: 34 * u, fontSize: 26 * u, fontWeight: 500, color: "rgba(161,209,255,0.75)", letterSpacing: 0.2 * u }}>
              github.com/Louistuis/thermal-map
            </div>
          </>
        )}
      </div>
    </AbsoluteFill>
  );
};

// ---------- camera paths ----------
// Board points (top-view mm): die (207.8, 41.6); heat sink centre (239.5, 41); battery (152, 124); map centre (152, 107.5).
function paths(tall: boolean) {
  const z = tall ? 0.86 : 1; // the 4:5 frame is narrower: come in a little closer on the parts
  const map = (t: number, vw: number) => kmm(t, 152, 107.5, vw);
  return {
    idle: [
      kf(1.9, 0.5, 0.5, 1.0),
      kf(at(13) - 0.2, 0.49, 0.5, 0.97),
      kf(at(22) - 0.3, 0.47, 0.5, tall ? 0.78 : 0.93),
      map(at(22) + 0.45, tall ? 0.66 : 0.78),
      map(at(30) - 0.1, tall ? 0.64 : 0.75),
      kmm(at(37), 214, 46, 0.6 * z),
      kmm(at(38) - 0.1, DIE.x, DIE.y, 0.42 * z),
      kmm(at(40) - 0.55, DIE.x + 2, DIE.y, 0.41 * z),
      kmm(at(40) + 0.05, 238, 42, 0.44 * z),
      kmm(at(43) - 0.5, 238, 43, 0.45 * z),
      kmm(at(43) + 0.15, 152, 128, tall ? 0.6 : 0.66),
      map(at(45) + 0.55, tall ? 0.66 : 0.8),
      map(at(56), tall ? 0.64 : 0.77),
    ],
    load: [
      kmm(at(56) - 0.25, 222, 62, 0.62 * z),
      kmm(at(63), 212, 76, 0.6 * z),
      map(at(68) + 0.5, tall ? 0.66 : 0.8),
      kmm(at(75) - 0.1, DIE.x, DIE.y + 6, 0.48 * z),
      kmm(at(79) + 0.2, 200, 60, 0.6 * z),
      kmm(at(80) + 0.6, 228, 40, 0.4 * z),
      kmm(at(98), 226, 40, 0.37 * z),
    ],
    cased: [map(at(98) - 0.4, tall ? 0.7 : 0.84), map(at(109) + 1.5, tall ? 0.64 : 0.77)],
  };
}

export const Film: React.FC<{ tall?: boolean }> = ({ tall = false }) => {
  const p = paths(tall);
  const f = (s: number) => Math.round(s * FPS);
  const idleTo = at(56) + 0.35, loadFrom = at(56) - 0.3;
  const loadTo = at(98) + 0.25, caseFrom = at(98) - 0.4;
  const endFrom = at(109) - 0.3;
  return (
    <AbsoluteFill style={{ background: BG }}>
      <Sequence from={f(1.9)} durationInFrames={f(idleTo - 1.9)}>
        <Section src="clips/idle.mp4" from={1.9} to={idleTo} keys={p.idle} fadeIn={0.5} Marks={IdleMarks} tall={tall} />
      </Sequence>
      <Sequence from={f(loadFrom)} durationInFrames={f(loadTo - loadFrom)}>
        <Section src="clips/load.mp4" from={loadFrom} to={loadTo} keys={p.load} fadeIn={0.6} Marks={LoadMarks} tall={tall} />
      </Sequence>
      <Sequence from={f(caseFrom)} durationInFrames={f(DURATION_S - caseFrom)}>
        <Section src="clips/case.mp4" from={caseFrom} to={DURATION_S} keys={p.cased} fadeIn={0.6} Marks={CaseMarks} tall={tall} />
      </Sequence>

      {tall && (
        <AbsoluteFill
          style={{ background: `linear-gradient(to bottom, ${BG} 0%, ${BG} 17%, rgba(13,13,16,0) 22%, rgba(13,13,16,0) 79%, ${BG} 84%, ${BG} 100%)` }}
        />
      )}

      <Sequence from={0} durationInFrames={f(2.4)}>
        <Card len={2.4} />
      </Sequence>
      <Sequence from={f(endFrom)} durationInFrames={f(DURATION_S - endFrom)}>
        <Card len={DURATION_S - endFrom} end />
      </Sequence>

      {timeline.phrases.map((ph, i) => (
        <Sequence key={i} from={f(ph.at)} durationInFrames={f(ph.src[1] - ph.src[0]) + 2}>
          <Audio src={staticFile("vo.mp3")} trimBefore={f(ph.src[0])} trimAfter={f(ph.src[1])} />
        </Sequence>
      ))}
    </AbsoluteFill>
  );
};
