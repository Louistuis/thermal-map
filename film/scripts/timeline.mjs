// Builds the film timeline from the narration's word timings: cuts the take into phrases, packs them with
// short gaps (dead air removed), and maps every word to film time. Film.tsx and music.mjs both read the result.
//   node film/scripts/timeline.mjs   ->  film/public/timeline.json
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const { words } = JSON.parse(readFileSync(join(root, "public/vo.json"), "utf8"));

// [first word, last word, gap before this phrase in seconds]
const PHRASES = [
  [0, 8, 0.55], //   Inside a MacBook Air, 205 sensors are measuring heat.
  [9, 16, 0.36], //  Thermal Map reads every one of them, live.
  [17, 24, 0.4], //  Each reading sits on the part it measures:
  [25, 26, 0.3], //  the chip,
  [27, 29, 0.3], //  the heat sink,
  [30, 31, 0.3], //  the battery.
  [32, 42, 0.42], // In between, it solves the heat equation five times a second.
  [43, 54, 0.4], //  Heat races through the aluminum heat sink and crawls through the battery.
  [55, 66, 0.42], // Put it under load and watch the M3 heat up and spread.
  [67, 85, 0.45], // To keep it honest, we hide sensors from the model, and it predicts them to within about two degrees,
  [86, 96, 0.36], // or look at the outside the way a thermal camera would.
  [97, 102, 0.6], // Thermal Map, free and open source.
];
const HEAD = 0.05, TAIL = 0.14, END_HOLD = 2.1;

let t = 0;
const phrases = [];
const filmWords = [];
PHRASES.forEach(([a, b, gap], i) => {
  const nextStart = i + 1 < PHRASES.length ? words[PHRASES[i + 1][0]].start : Infinity;
  const src0 = Math.max(0, words[a].start - HEAD);
  const src1 = Math.min(words[b].end + TAIL, nextStart - 0.02);
  t += gap;
  const at = t;
  phrases.push({ words: [a, b], src: [+src0.toFixed(3), +src1.toFixed(3)], at: +at.toFixed(3) });
  for (let w = a; w <= b; w++) {
    filmWords[w] = { i: w, text: words[w].text, t0: +(at + words[w].start - src0).toFixed(3), t1: +(at + words[w].end - src0).toFixed(3) };
  }
  t = at + (src1 - src0);
});
const total = +(t + END_HOLD).toFixed(2);
writeFileSync(join(root, "public/timeline.json"), JSON.stringify({ total, phrases, words: filmWords }, null, 1) + "\n");
console.log(`film ${total} s, narration ${t.toFixed(2)} s`);
for (const p of phrases) console.log(`${p.at.toFixed(2)}  ${filmWords[p.words[0]].text} ... ${filmWords[p.words[1]].text}`);
