#!/usr/bin/env bash
# Build the three Homelancer ship slots from fleet-sheet GLBs.
#
#   tools/shipkit/make_ships.sh look SHEET.glb [--pieces | --grid 4x4]     → shipkit_out/clusters.png (numbered ships)
#   tools/shipkit/make_ships.sh build NAME SHEET.glb MODE NUMBER [flip]     NAME = cargo | enemy | carrier
#
# What shipped in v1.2 (see README.md):
#   build enemy   c4c7fd83…glb --grid=4x4 11
#   build cargo   c6c661d8…glb --pieces   16 flip
#   build carrier c6c661d8…glb --pieces   22
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
GODOT="${GODOT:-$ROOT/../godot/Godot_v4.3-stable_linux.x86_64}"
OUT="${OUT:-shipkit_out}"; mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
cmd="$1"; shift
if [ "$cmd" = look ]; then
  src="$1"; shift
  python3 "$HERE/shipkit.py" inspect "$src" --out "$OUT" "$@"
  exit 0
fi
name="$1" src="$2" mode="$3" num="$4" flip="${5:-}"
mode="${mode/=/ }"
case "$name" in
  cargo)   slot=assets/ships/civilian/cargo_ship.glb; tris=6000;  tex=512;  taper=0.65 ;;
  enemy)   slot=assets/ships/enemy/enemy_fleet.glb;   tris=5000;  tex=512;  taper=0.8 ;;
  carrier) slot=assets/ships/civilian/carrier.glb;    tris=12000; tex=1024; taper=0.7 ;;
  *) echo "NAME must be cargo, enemy or carrier"; exit 1 ;;
esac
GP="$(mktemp -d)"; echo 'config_version=5' > "$GP/project.godot"
python3 "$HERE/shipkit.py" export "$src" $mode --cluster "$num" --axis y --taper "${TAPER:-$taper}" \
    ${flip:+--flip} --name "$name" --out "$OUT/${name}_full.glb" --preview "$OUT/${name}_preview.png"
"$GODOT" --headless --path "$GP" --script "$HERE/decimate.gd" -- "$OUT/${name}_full.glb" "$OUT/${name}_lo.glb" "${TRIS:-$tris}" 2>&1 | grep DECIMATE
python3 "$HERE/shipkit.py" repack "$OUT/${name}_lo.glb" --textures-from "$OUT/${name}_full.glb" --out "$ROOT/$slot" --name "$name" --tex "$tex"
rm -rf "$GP"
# fresh texture import, stored compressed (lossy WebP) so the web download stays small
base="${slot%.glb}"
rm -f "$ROOT/${base}"_[0-9].jpg "$ROOT/${base}"_[0-9].jpg.import "$ROOT/${base}"_[0-9].png "$ROOT/${base}"_[0-9].png.import
"$GODOT" --headless --import --path "$ROOT" >/dev/null 2>&1 || true
sed -i 's/^compress\/mode=0/compress\/mode=1/; s/^compress\/lossy_quality=.*/compress\/lossy_quality=0.8/' "$ROOT/${base}"_[0-9].*.import
"$GODOT" --headless --import --path "$ROOT" >/dev/null 2>&1 || true
echo "done: $slot"
