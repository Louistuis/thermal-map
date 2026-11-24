#!/bin/zsh
# Two-pass loudness normalisation to -14 LUFS (true peak -1.5 dBTP), video stream copied.
#   Tools/demo/loudnorm.sh in.mp4 out.mp4
set -e
IN="${1:?in}"; OUT="${2:?out}"
read I TP LRA TH OFF < <(ffmpeg -hide_banner -i "$IN" -af loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json -f null - 2>&1 \
  | sed -n '/^{/,/^}/p' \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['input_i'], d['input_tp'], d['input_lra'], d['input_thresh'], d['target_offset'])")
ffmpeg -y -loglevel error -i "$IN" -c:v copy \
  -af "loudnorm=I=-14:TP=-1.5:LRA=11:measured_I=${I}:measured_TP=${TP}:measured_LRA=${LRA}:measured_thresh=${TH}:offset=${OFF}:linear=true,aresample=48000" \
  -c:a aac -b:a 256k -movflags +faststart "$OUT"
ffmpeg -hide_banner -i "$OUT" -af ebur128=peak=true -f null - 2>&1 | grep -E "^\s+I:|^\s+Peak:" | tr -s ' ' | tr '\n' ' '
echo " $OUT"
