#!/bin/zsh
# Records live demo frames headlessly (no window) while a short CPU load heats the Mac.
#   Tools/demo/record-demo.sh "<path to Thermal Map.app>" <frames dir>
# Timeline (recorded seconds): idle 0-8, all-core load 8-100, BOTTOM CASE from 70, TOP + INTERNAL from 125, stop at 150.
set -e
APP="${1:?app path}"; FRAMES="${2:?frames dir}"
BIN="$APP/Contents/MacOS/ThermalMap"
rm -rf "$FRAMES"; mkdir -p "$FRAMES"
LOAD_PIDS=()
cleanup() { for p in $LOAD_PIDS; do kill $p 2>/dev/null || true; done }
trap cleanup EXIT INT TERM
"$BIN" --record="$FRAMES" --seconds=150 --fps=2 --at=70:surface --at=125:internal --at=125:top &
REC=$!
sleep 11   # 3 s warm-up inside the recorder + 8 s idle
for i in {1..$(sysctl -n hw.ncpu)}; do yes > /dev/null & LOAD_PIDS+=$!; done
echo "load on ($#LOAD_PIDS processes)"
sleep 92
cleanup; LOAD_PIDS=()
echo "load off"
wait $REC
if pgrep -x yes >/dev/null; then echo "warning: yes still running"; else echo "no load processes left"; fi
