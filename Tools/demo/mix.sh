#!/bin/zsh
# Final audio: lays the synthesized music bed (Tools/demo/music.mjs) under the narration, ducks it while
# the voice speaks, then normalises the whole mix to -14 LUFS / -1.5 dBTP. Video is copied untouched.
#   Tools/demo/mix.sh <film render with narration.mp4> <music.wav> <out.mp4> [music gain dB, default -13]
set -e
IN="${1:?film}"; MUSIC="${2:?music}"; OUT="${3:?out}"; GAIN="${4:--13}"
TMP="${OUT:r}.premix.mp4"
ffmpeg -y -loglevel error -i "$IN" -i "$MUSIC" -filter_complex "\
[0:a]aresample=48000,asplit=2[vo][key];\
[1:a]aresample=48000,volume=${GAIN}dB[m];\
[m][key]sidechaincompress=threshold=0.015:ratio=5:attack=25:release=420:knee=4[md];\
[vo][md]amix=inputs=2:normalize=0:duration=first[a]" \
  -map 0:v -map "[a]" -c:v copy -c:a pcm_s24le -f mov "$TMP"
"${0:A:h}/loudnorm.sh" "$TMP" "$OUT"
rm -f "$TMP"
