// Lists the annotation moments (film seconds, from the narration timing) and renders a still of each
// for checking, into film/out/marks/.   node film/scripts/marks.mjs [Wide|Tall] [--no-render]
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const tl = JSON.parse(readFileSync(join(root, "public/timeline.json"), "utf8"));
const at = (i) => tl.words[i].t0;
const comp = process.argv[2] ?? "Wide";
export const MARKS = [
  ["MacBook Air 13-inch outline", at(8) - 0.15, 1.0],
  ["205 sensors ripple", at(14) - 0.1, 0.45],
  ["M3 rectangle", at(38) - 0.15, 0.7],
  ["Heat sink rectangle", at(40) - 0.15, 0.8],
  ["Battery cells", at(43) - 0.15, 0.75],
  ["Heat equation sweep", at(48) - 0.1, 0.5],
  ["Five solver passes", at(52) - 0.05, 0.5],
  ["Fast flow, heat sink", at(57) - 0.2, 1.0],
  ["Slow flow, battery", at(64) + 0.2, 0.8],
  ["Under load, M3 circle", at(75) - 0.15, 0.7],
  ["Spread rings", at(79) - 0.25, 0.5],
  ["Hidden sensors", at(85) - 0.1, 0.6],
  ["Predicted", at(92) - 0.1, 0.7],
  ["Within 2 °C", at(96) - 0.1, 0.5],
  ["Bottom case outline", at(102) - 0.2, 1.2],
  ["End card", at(109) - 0.3, 1.6],
];
mkdirSync(join(root, "out/marks"), { recursive: true });
for (const [name, t, look] of MARKS) {
  const frame = Math.round((t + look) * 30);
  console.log(`${t.toFixed(2)} s  ${name}  (still at ${(t + look).toFixed(2)} s, frame ${frame})`);
  if (process.argv.includes("--no-render")) continue;
  const out = join(root, `out/marks/${comp}-${String(frame).padStart(4, "0")}.jpg`);
  execFileSync(join(root, "node_modules/.bin/remotion"), ["still", "src/index.ts", comp, out, `--frame=${frame}`, "--log=error"], { cwd: root, stdio: "ignore" });
}
