#!/bin/zsh
# Turns recorded frames into the demo videos: 1920x1080 (X, Reddit) and 1080x1350 (4:5 feed cut). Silent, H.264.
#   Tools/demo/make-demo.sh <frames dir> <out dir>
# Env: PLAY=12 (recorded frames shown per second; 2 fps capture at 12 = 6x speed)
#      URL=github.com/Louistuis/thermal-map
#      CROP=1240:1000:110:70 (map region of a 1920x1080 frame used for the 4:5 cut, w:h:x:y)
set -e
HERE="${0:A:h}"
FRAMES="${1:?frames dir}"; OUT="${2:?out dir}"
PLAY="${PLAY:-12}"; URL="${URL:-github.com/Louistuis/thermal-map}"; CROP="${CROP:-1240:1000:110:70}"
TITLE_S=2.6; END_S=3.6; XF=0.5; BG=0x0b0b0d
mkdir -p "$OUT/.work"; W="$OUT/.work"
[[ "$W/cards" -nt "$HERE/cards.swift" ]] || swiftc -O "$HERE/cards.swift" -o "$W/cards"

render() {  # render <WxH> <tag> <crop filter or empty> <out.mp4>
  local SZ=$1 TAG=$2 PRE=$3 DST=$4
  local WW=${SZ%x*} HH=${SZ#*x}
  "$W/cards" title "$W/title-$TAG.png" $SZ "Live thermal map · MacBook Air M3" "Thermal Map" "Every temperature sensor in your Mac, as a thermal camera view."
  "$W/cards" end "$W/end-$TAG.png" $SZ "Free and open source · macOS 14+" "$URL" "Native Swift. Built for MacBook Air 13-inch M3."
  # footage with caption overlays
  local inputs=(-framerate $PLAY -i "$FRAMES/frame_%05d.png")
  local chain="[0:v]${PRE}scale=${WW}:${HH}:force_original_aspect_ratio=decrease,pad=${WW}:${HH}:(ow-iw)/2:(oh-ih)/2:color=$BG,fps=30,format=rgba[v0]"
  local n=0 S E POS K T
  while IFS='|' read -r S E POS K T; do
    [[ -z "$S" || "$S" == \#* ]] && continue
    n=$((n+1))
    "$W/cards" caption "$W/cap$n-$TAG.png" $SZ "$K" "$T" "$POS"
    inputs+=(-loop 1 -framerate 30 -i "$W/cap$n-$TAG.png")
    chain+=";[$n:v]format=rgba,fade=in:st=$S:d=0.35:alpha=1,fade=out:st=$(( E - 0.35 )):d=0.35:alpha=1[c$n]"
    chain+=";[v$((n-1))][c$n]overlay=0:0:shortest=1[v$n]"
  done < "$HERE/captions.txt"
  chain+=";[v$n]format=yuv420p[vout]"
  ffmpeg -y -loglevel error "${inputs[@]}" -filter_complex "$chain" -map "[vout]" -c:v libx264 -crf 16 -preset slow -r 30 "$W/footage-$TAG.mp4"
  local FD=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$W/footage-$TAG.mp4")
  # title, footage, end card joined with cross-fades
  ffmpeg -y -loglevel error \
    -loop 1 -framerate 30 -t $TITLE_S -i "$W/title-$TAG.png" -i "$W/footage-$TAG.mp4" -loop 1 -framerate 30 -t $END_S -i "$W/end-$TAG.png" \
    -filter_complex "[0:v]format=yuv420p,settb=AVTB,fps=30[a];[1:v]format=yuv420p,settb=AVTB,fps=30[b];[2:v]format=yuv420p,settb=AVTB,fps=30[c];[a][b]xfade=transition=fade:duration=$XF:offset=$(( TITLE_S - XF ))[ab];[ab][c]xfade=transition=fade:duration=$XF:offset=$(( TITLE_S + FD - 2*XF ))[v]" \
    -map "[v]" -c:v libx264 -crf 18 -preset slow -profile:v high -pix_fmt yuv420p -movflags +faststart -r 30 "$DST"
  echo "$DST  $(ffprobe -v error -show_entries format=duration -of csv=p=0 "$DST") s  $(du -h "$DST" | cut -f1)"
}

render 1920x1080 wide "" "$OUT/thermal-map-demo-1080p.mp4"
render 1080x1350 tall "crop=$CROP," "$OUT/thermal-map-demo-4x5.mp4"
