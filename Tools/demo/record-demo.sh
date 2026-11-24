#!/bin/zsh
# Records live demo frames headlessly (no window) while a short CPU load heats the Mac.
#   Tools/demo/record-demo.sh "<path to Thermal Map.app>" <frames dir>
# Frames are 2458x1382 JPEGs at 3 fps, big enough for slow zooms in the edit.
# Timeline (recorded seconds): idle 0-10, all-core load 10-95, Bottom case from 62,
# Top + Internal from 120, stop at 140. RANGE=auto records with the auto colour range (default: fixed 20-100 C).
set -e
APP="${1:?app path}"; FRAMES="${2:?frames dir}"
rm -rf "$FRAMES"; mkdir -p "$FRAMES"
# run a renamed copy, so `killall ThermalMap` (relaunching the app while working on it) can't end the take
BIN="$FRAMES/../tm-recorder"
cp "$APP/Contents/MacOS/ThermalMap" "$BIN"
LOAD_PIDS=()
cleanup() { for p in $LOAD_PIDS; do kill $p 2>/dev/null || true; done }
trap cleanup EXIT INT TERM
"$BIN" --record="$FRAMES" --seconds=140 --fps=3 --scale=1.6 --format=jpg \
  --at=0:${RANGE:-fixed} --at=62:surface --at=62:auto --at=120:internal --at=120:top --at=120:fixed &
REC=$!
sleep 13   # 3 s warm-up inside the recorder + 10 s idle
for i in {1..$(sysctl -n hw.ncpu)}; do yes > /dev/null & LOAD_PIDS+=$!; done
echo "load on ($#LOAD_PIDS processes)"
sleep 85
cleanup; LOAD_PIDS=()
echo "load off"
wait $REC || echo "recorder exited with $?"
if pgrep -x yes >/dev/null; then echo "warning: yes still running"; else echo "no load processes left"; fi
ls "$FRAMES" | wc -l
