#!/bin/zsh
# Cuts recorded frames (Tools/demo/record-demo.sh) into the footage clips the film uses, at 30 fps with
# frame blending so 3 fps captures play back smoothly at any speed.
#   Tools/demo/film-clips.sh <frames dir> [frames dir for the load shot]
# The load shot can come from a second take recorded with a fixed colour range (record-demo.sh does
# --at=0:fixed), so the heat visibly rises instead of the auto range rescaling it away.
# Each clip: recorded start..end seconds squeezed into a screen duration (see film/src/Film.tsx).
set -e
zmodload zsh/mathfunc
FRAMES="${1:?frames dir}"; LOADFRAMES="${2:-$1}"; FILM="${0:A:h}/../../film"
OUT="$FILM/public/clips"; mkdir -p "$OUT"
REC_FPS=3

clip() {  # clip <name> <recorded start s> <recorded end s> <screen seconds> [frames dir]
  local NAME=$1 A=$2 B=$3 D=$4 SRC=${5:-$FRAMES}
  local first=$(( int(A * REC_FPS) )) count=$(( int((B - A) * REC_FPS) ))
  local rate=$(( count / D ))
  ffmpeg -y -loglevel error -framerate $rate -start_number $first -i "$SRC/frame_%05d.jpg" \
    -vf "trim=end_frame=$count,setpts=PTS-STARTPTS,crop=trunc(iw/2)*2:trunc(ih/2)*2:0:0,framerate=fps=30:interp_start=0:interp_end=255:scene=100,format=yuv420p" \
    -c:v libx264 -crf 14 -preset slow -g 30 -movflags +faststart "$OUT/$NAME.mp4"
  echo "$NAME: recorded ${A}-${B} s ($count frames) -> $(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/$NAME.mp4") s"
}

clip idle   0   10  16.9                  # internals at idle: wide, the parts, the solver
clip load   10  62  13.6  "$LOADFRAMES"   # flow, under load, the held-out sensor test
clip case   64  110 7.6                   # bottom case, then the end card
