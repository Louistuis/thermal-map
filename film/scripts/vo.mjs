// Narration for the demo film: ElevenLabs text-to-speech, then Scribe word timings.
//   node --env-file=<file with ELEVENLABS_API_KEY> film/scripts/vo.mjs
// Writes film/public/vo.mp3 and film/public/vo.json ({ words: [{ text, start, end }] } in seconds).
// The key is read from the environment only and never printed.
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const key = process.env.ELEVENLABS_API_KEY;
if (!key) { console.error("ELEVENLABS_API_KEY is not set"); process.exit(1); }

const cfg = JSON.parse(readFileSync(join(root, "narration.json"), "utf8"));
const text = cfg.script.join(" ");
console.log(`Voice ${cfg.voice.name} (${cfg.voice.model}), ${text.length} characters`);

const tts = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${cfg.voice.id}?output_format=mp3_44100_128`, {
  method: "POST",
  headers: { "xi-api-key": key, "content-type": "application/json", accept: "audio/mpeg" },
  body: JSON.stringify({
    text,
    model_id: cfg.voice.model,
    voice_settings: { stability: cfg.voice.stability, similarity_boost: cfg.voice.similarityBoost, style: cfg.voice.style ?? 0 },
  }),
});
if (!tts.ok) { console.error(`TTS failed: ${tts.status} ${await tts.text()}`); process.exit(1); }
const mp3 = Buffer.from(await tts.arrayBuffer());
writeFileSync(join(root, "public/vo.mp3"), mp3);

const form = new FormData();
form.append("model_id", "scribe_v1");
form.append("timestamps_granularity", "word");
form.append("file", new Blob([mp3], { type: "audio/mpeg" }), "vo.mp3");
const stt = await fetch("https://api.elevenlabs.io/v1/speech-to-text", { method: "POST", headers: { "xi-api-key": key }, body: form });
if (!stt.ok) { console.error(`Scribe failed: ${stt.status} ${await stt.text()}`); process.exit(1); }
const words = ((await stt.json()).words ?? []).filter((w) => w.type === "word").map((w) => ({ text: w.text, start: w.start, end: w.end }));
writeFileSync(join(root, "public/vo.json"), JSON.stringify({ words }, null, 1) + "\n");
console.log(`Wrote public/vo.mp3 and ${words.length} word timings`);
