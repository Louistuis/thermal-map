// Finds where the map sits inside a recorded frame, so annotations can be drawn in board millimetres.
//   node film/scripts/measure.mjs <frame.jpg>
// Prints the light profile across the shell edges; the shell outline is the brightest thin line there.
import { execFileSync } from "node:child_process";

const file = process.argv[2];
const probe = execFileSync("ffprobe", ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0", file]).toString().trim();
const [W, H] = probe.split(",").map(Number);
const g = execFileSync("ffmpeg", ["-loglevel", "error", "-i", file, "-f", "rawvideo", "-pix_fmt", "gray", "-"], { maxBuffer: 64 << 20 });
const at = (x, y) => g[y * W + x];

// strongest local peaks (thin bright lines) along a scan line
function peaks(vals, from, to, n = 4) {
  const out = [];
  for (let i = from + 1; i < to - 1; i++) {
    const d = vals[i] - (vals[i - 3] + vals[i + 3]) / 2;
    out.push([d, i, vals[i]]);
  }
  return out.sort((a, b) => b[0] - a[0]).slice(0, n).map(([d, i, v]) => `${i}(+${d.toFixed(0)},${v})`).join(" ");
}
const y = +(process.argv[3] ?? Math.round(H * 0.62));
const x = +(process.argv[4] ?? Math.round(W * 0.385));
const row = Array.from({ length: W }, (_, i) => at(i, y));
const col = Array.from({ length: H }, (_, i) => at(x, i));
console.log(`${W}x${H}  row y=${y}  col x=${x}`);
console.log("left edge  ", peaks(row, Math.round(W * 0.04), Math.round(W * 0.14)));
console.log("right edge ", peaks(row, Math.round(W * 0.62), Math.round(W * 0.74)));
console.log("top edge   ", peaks(col, Math.round(H * 0.08), Math.round(H * 0.18)));
console.log("bottom edge", peaks(col, Math.round(H * 0.82), Math.round(H * 0.93)));
