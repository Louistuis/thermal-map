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

// Keynote-style demo: real headless footage, slow camera moves, a calm narrator, almost no text.
// All times below are in seconds on the film timeline. Clips are made by Tools/demo/film-clips.sh.

export const FPS = 30;
export const DURATION_S = 43;

// Source frame size of the footage clips (recorder: 1536x864 layout at scale 1.6).
const SW = 2458;
const SH = 1382;
const BG = "#0d0d10";
const FONT = '"SF Pro Display", -apple-system, BlinkMacSystemFont, system-ui, sans-serif';

// Narration phrases: [start, end] inside vo.mp3, and where each one lands in the film.
const PHRASES: { src: [number, number]; at: number }[] = [
  { src: [0.0, 4.4], at: 0.8 }, // Inside a MacBook Air, 205 sensors are quietly measuring heat.
  { src: [4.8, 7.95], at: 5.6 }, // Thermal Map reads every one of them, live.
  { src: [8.35, 17.65], at: 9.4 }, // Each reading sits on the part it measures ... between.
  { src: [17.85, 22.3], at: 19.8 }, // Put it under load ... and spread.
  { src: [22.65, 25.6], at: 30.6 }, // Or look at the outside, the way a thermal camera would.
  { src: [26.05, 28.79], at: 37.4 }, // Thermal Map, free and open source.
];

// A camera keyframe: centre (cx, cy) as fractions of the source frame, vw = visible width as a fraction of it.
type Key = { t: number; cx: number; cy: number; vw: number };

const ease = Easing.bezier(0.45, 0, 0.25, 1);

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

// Plays a footage clip through a moving camera. `from` is the film time the clip starts at.
const Shot: React.FC<{ src: string; from: number; keys: Key[]; fadeIn: number; fadeOut?: [number, number] }> = ({
  src,
  from,
  keys,
  fadeIn,
  fadeOut,
}) => {
  const frame = useCurrentFrame();
  const { width, height } = useVideoConfig();
  const t = from + frame / FPS;
  const c = camAt(keys, t);
  const s = width / (c.vw * SW);
  const x = width / 2 - c.cx * SW * s;
  const y = height / 2 - c.cy * SH * s;
  let opacity = interpolate(t, [from, from + fadeIn], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  if (fadeOut) opacity *= interpolate(t, fadeOut, [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <AbsoluteFill style={{ opacity }}>
      <div style={{ position: "absolute", left: 0, top: 0, width: SW, height: SH, transformOrigin: "0 0", transform: `translate(${x}px, ${y}px) scale(${s})` }}>
        <OffthreadVideo src={staticFile(src)} muted style={{ width: SW, height: SH }} />
      </div>
    </AbsoluteFill>
  );
};

// Small sentence-case label, centred low over a soft shade, fades in and out.
const Label: React.FC<{ text: string; len: number }> = ({ text, len }) => {
  const frame = useCurrentFrame();
  const { width, height } = useVideoConfig();
  const t = frame / FPS;
  const o = interpolate(t, [0, 0.9, len - 0.9, len], [0, 1, 1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const u = Math.min(width, height) / 1080;
  return (
    <AbsoluteFill style={{ opacity: o }}>
      <AbsoluteFill style={{ top: height * 0.62, background: `linear-gradient(to bottom, rgba(13,13,16,0), rgba(13,13,16,0.78))` }} />
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "flex-end", paddingBottom: height * 0.075 }}>
        <div style={{ fontFamily: FONT, fontSize: 40 * u, fontWeight: 500, color: "rgba(255,255,255,0.94)", letterSpacing: -0.3 * u, transform: `translateY(${(1 - o) * 8 * u}px)` }}>
          {text}
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

// Title and end cards. The title card's background dissolves into the first shot; the end card's fades up over the last.
const Card: React.FC<{ len: number; end?: boolean }> = ({ len, end }) => {
  const frame = useCurrentFrame();
  const { width, height } = useVideoConfig();
  const t = frame / FPS;
  const u = Math.min(width, height) / 1080;
  const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
  const bg = end ? interpolate(t, [0, 0.8], [0, 1], clamp) : interpolate(t, [len - 0.8, len], [1, 0], clamp);
  const text = end
    ? interpolate(t, [0.6, 1.6, len - 1.2, len - 0.4], [0, 1, 1, 0], clamp)
    : interpolate(t, [0.2, 1.1, len - 1.4, len - 0.7], [0, 1, 1, 0], clamp);
  const rise = interpolate(t, [end ? 0.6 : 0.2, end ? 2.0 : 1.6], [10, 0], { ...clamp, easing: ease });
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", fontFamily: FONT }}>
      <AbsoluteFill style={{ background: BG, opacity: bg }} />
      <div style={{ opacity: text, transform: `translateY(${rise * u}px)`, textAlign: "center" }}>
        <div style={{ fontSize: (end ? 92 : 104) * u, fontWeight: 600, color: "#fff", letterSpacing: -2.2 * u }}>Thermal Map</div>
        {end && (
          <>
            <div style={{ marginTop: 18 * u, fontSize: 34 * u, fontWeight: 400, color: "rgba(255,255,255,0.62)" }}>Free and open source.</div>
            <div style={{ marginTop: 34 * u, fontSize: 26 * u, fontWeight: 500, color: "rgba(255,255,255,0.46)", letterSpacing: 0.2 * u }}>
              github.com/Louistuis/thermal-map
            </div>
          </>
        )}
      </div>
    </AbsoluteFill>
  );
};

// Camera paths, measured on the recorded 1536x864 layout: map shell x 0.09-0.68, y 0.13-0.87,
// M3 ~(0.28, 0.27), heat-sink sensors ~(0.21, 0.30), battery cells ~(0.38, 0.48). `tall` is the 4:5 cut.
function paths(tall: boolean) {
  const k = (t: number, cx: number, cy: number, vw: number): Key => ({ t, cx, cy, vw });
  if (!tall) {
    return {
      wide: [k(2.8, 0.5, 0.5, 1.0), k(10.2, 0.45, 0.505, 0.9)],
      close: [k(9.4, 0.38, 0.51, 0.8), k(11.9, 0.29, 0.31, 0.52), k(13.2, 0.23, 0.32, 0.5), k(14.6, 0.36, 0.47, 0.5), k(18.0, 0.38, 0.51, 0.76), k(20.6, 0.38, 0.51, 0.78)],
      load: [k(19.8, 0.38, 0.51, 0.78), k(30.8, 0.34, 0.44, 0.64)],
      cased: [k(30.0, 0.38, 0.51, 0.78), k(37.6, 0.37, 0.5, 0.7)],
    };
  }
  return {
    wide: [k(2.8, 0.39, 0.5, 0.68), k(10.2, 0.39, 0.5, 0.64)],
    close: [k(9.4, 0.385, 0.5, 0.64), k(11.9, 0.29, 0.31, 0.46), k(13.2, 0.24, 0.32, 0.44), k(14.6, 0.37, 0.47, 0.46), k(18.0, 0.385, 0.5, 0.62), k(20.6, 0.385, 0.5, 0.64)],
    load: [k(19.8, 0.385, 0.5, 0.64), k(30.8, 0.35, 0.42, 0.52)],
    cased: [k(30.0, 0.385, 0.5, 0.64), k(37.6, 0.38, 0.48, 0.58)],
  };
}

export const Film: React.FC<{ tall?: boolean }> = ({ tall = false }) => {
  const p = paths(tall);
  const f = (s: number) => Math.round(s * FPS);
  return (
    <AbsoluteFill style={{ background: BG }}>
      <Sequence from={f(2.8)} durationInFrames={f(7.4)}>
        <Shot src="clips/idle.mp4" from={2.8} keys={p.wide} fadeIn={0.8} />
      </Sequence>
      <Sequence from={f(9.4)} durationInFrames={f(11.2)}>
        <Shot src="clips/idle-close.mp4" from={9.4} keys={p.close} fadeIn={0.8} />
      </Sequence>
      <Sequence from={f(19.8)} durationInFrames={f(11.0)}>
        <Shot src="clips/load.mp4" from={19.8} keys={p.load} fadeIn={0.8} />
      </Sequence>
      <Sequence from={f(30.0)} durationInFrames={f(7.6)}>
        <Shot src="clips/case.mp4" from={30.0} keys={p.cased} fadeIn={0.8} />
      </Sequence>

      {tall && (
        <AbsoluteFill
          style={{
            background: `linear-gradient(to bottom, ${BG} 0%, ${BG} 20.5%, rgba(13,13,16,0) 24%, rgba(13,13,16,0) 76.5%, ${BG} 81%, ${BG} 100%)`,
          }}
        />
      )}
      <Sequence from={0} durationInFrames={f(3.6)}>
        <Card len={3.6} />
      </Sequence>
      <Sequence from={f(36.8)} durationInFrames={f(DURATION_S - 36.8)}>
        <Card len={DURATION_S - 36.8} end />
      </Sequence>

      <Sequence from={f(21.0)} durationInFrames={f(4.6)}>
        <Label text="Under load" len={4.6} />
      </Sequence>
      <Sequence from={f(31.2)} durationInFrames={f(4.4)}>
        <Label text="Bottom case" len={4.4} />
      </Sequence>

      {PHRASES.map((ph, i) => (
        <Sequence key={i} from={f(ph.at)} durationInFrames={f(ph.src[1] - ph.src[0]) + 2}>
          <Audio src={staticFile("vo.mp3")} trimBefore={f(ph.src[0])} trimAfter={f(ph.src[1])} />
        </Sequence>
      ))}
    </AbsoluteFill>
  );
};
