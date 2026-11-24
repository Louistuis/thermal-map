#!/bin/zsh
# Headless render matrix: every view and toggle combination, checked by check_renders.py.
# Usage: Tools/test/render-matrix.sh [binary] [outdir]
set -e
BIN="${1:-build/ThermalMap}"
OUT="${2:-${TMPDIR:-/tmp}/thermalmap-renders}"
mkdir -p "$OUT"
r() { local name=$1; shift; "$BIN" --render="$OUT/$name.png" "$@" >/dev/null && echo "$name $*" >> "$OUT/index.txt"; }
: > "$OUT/index.txt"
# alignment set: rainbow + fixed range so the field is never near-black
for side in bottom top; do for mode in internal surface; do
  flags=(--palette=rainbow --fixed-range); [[ $side == top ]] && flags+=--top; [[ $mode == surface ]] && flags+=--surface
  r "align-$side-$mode-all" $flags
  r "align-$side-$mode-noiso" $flags --no-isotherms
  r "align-$side-$mode-none" $flags --no-isotherms --no-parts --no-sensors
done; done
r align-small --palette=rainbow --fixed-range --size=1180x760
r align-large --palette=rainbow --fixed-range --size=2200x1300 --no-isotherms
# looks
for p in ironbow rainbow arctic "white hot"; do r "palette-${p// /-}" --palette="$p"; done
r labels --labels
r highlight --hl=smc:TB0T
THERMALMAP_FAKE_MODEL=Mac16,1 r notice-other-mac
