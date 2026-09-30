#!/usr/bin/env bash
# Turn the multi-ship fleet GLB into the three Homelancer ship slots.
#
#   tools/shipkit/make_ships.sh fleet.glb                     # step 1: look — writes shipkit_out/overview.png + clusters.png
#   tools/shipkit/make_ships.sh fleet.glb CARGO ENEMY CARRIER # step 2: build — cluster numbers from step 1 (e.g. 4 1 7, or 4,5 for multi-part)
#
# Env knobs: TAPER (nose tip width, default 0.65), FLIP_<NAME>=1 to turn a ship around, TRIS_<NAME> polygon budget.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
GODOT="${GODOT:-$ROOT/../godot/Godot_v4.3-stable_linux.x86_64}"
SRC="$1"; shift || true
OUT="${OUT:-shipkit_out}"; mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
if [ $# -lt 3 ]; then
  python3 "$HERE/shipkit.py" inspect "$SRC" --out "$OUT"
  echo "Now pick the cluster numbers and run: $0 $SRC <cargo> <enemy> <carrier>"
  exit 0
fi
GP="$(mktemp -d)"; echo 'config_version=5' > "$GP/project.godot"
build() { # name cluster slot tris
  local name=$1 cl=$2 slot=$3 tris=$4 flipvar="FLIP_${1^^}" trisvar="TRIS_${1^^}"
  local flip=""; [ "${!flipvar:-0}" = 1 ] && flip="--flip"
  python3 "$HERE/shipkit.py" export "$SRC" --cluster "$cl" --name "$name" --out "$OUT/${name}_full.glb" \
      --taper "${TAPER:-0.65}" $flip --preview "$OUT/${name}_preview.png"
  "$GODOT" --headless --path "$GP" --script "$HERE/decimate.gd" -- "$OUT/${name}_full.glb" "$ROOT/$slot" "${!trisvar:-$tris}" 2>&1 | grep DECIMATE
}
mkdir -p "$OUT" "$ROOT/assets/ships/civilian" "$ROOT/assets/ships/enemy"
build cargo   "$1" assets/ships/civilian/cargo_ship.glb 6000
build enemy   "$2" assets/ships/enemy/enemy_fleet.glb  5000
build carrier "$3" assets/ships/civilian/carrier.glb   12000
rm -rf "$GP"
ls -la "$ROOT/assets/ships/civilian" "$ROOT/assets/ships/enemy"
