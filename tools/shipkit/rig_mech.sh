#!/bin/bash
# rig_mech.sh — Tripo mech/humanoid GLB -> game-ready rigged GLB (22-bone Godot humanoid, Idle + Walk).
#   rig_mech.sh look  IN.glb WORK/NAME          reduce (~18k tris), 2048 textures, measured front/side/top views
#                                               -> WORK/NAME_body.glb, WORK/NAME_grid.png (read joint x,y off it)
#   rig_mech.sh rig   WORK/NAME GUESS.json [--rule "Bone : cond" ...]   fill z, rig at 3 m, apply rigfix rules,
#                                               -> WORK/NAME_rigged.glb, WORK/NAME_bones.png, WORK/NAME_walk.png
# rigfix conditions are in the RIGGED model's units (3 m tall = 3x the 1 m numbers you read off the grid).
# Humans: add --human to 'rig' (soft joints, 1.8 m).  Needs GODOT=<Godot 4.3 binary> (default /home/claude/godot/...).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
GODOT="${GODOT:-/home/claude/godot/Godot_v4.3-stable_linux.x86_64}"; export GODOT
cmd=$1; shift
if [ "$cmd" = look ]; then
  in=$(realpath "$1"); out=$(realpath -m "$2"); mkdir -p "$(dirname "$out")"
  GP=$(mktemp -d); echo "config_version=5" > $GP/project.godot
  timeout 300 "$GODOT" --headless --path $GP --script "$HERE/decimate.gd" -- "$in" "${out}_lo.glb" ${TRIS:-31000} 2>&1 | grep DECIMATE
  python3 "$HERE/shipkit.py" repack "${out}_lo.glb" --textures-from "$in" --out "${out}_body.glb" --name body --tex ${TEX:-2048}
  STUDIO_ORTHO=1.05 STUDIO_VIEWS="0,0,1;1,0,0;0,1,0.001" bash "$HERE/studio.sh" "${out}_body.glb" "${out}_o" 900
  python3 "$HERE/grid.py" "${out}_o_sheet.png" "${out}_grid.png" 900 0,0.5,0,1.05 "x,y;-z,y;x,-z"
  echo "views: ${out}_grid.png  (front | side, front is left | top)"
elif [ "$cmd" = rig ]; then
  out=$(realpath -m "$1"); guess=$2; shift 2
  H=3.0; MECH=--mech
  if [ "$1" = --human ]; then H=1.8; MECH=""; shift; fi
  python3 "$HERE/auto_joints.py" "${out}_body.glb" "$guess" "${out}_joints.json" >/dev/null
  python3 "$HERE/rig_humanoid.py" "${out}_body.glb" "${out}_joints.json" "${out}_r0.glb" $MECH --height $H | tail -1
  if [ $# -gt 0 ]; then python3 "$HERE/rigfix.py" "${out}_r0.glb" "${out}_rigged.glb" "$@"; else cp "${out}_r0.glb" "${out}_rigged.glb"; fi
  python3 "$HERE/bonemap.py" "${out}_rigged.glb" "${out}_bones.png" $H >/dev/null 2>&1 || true
  for t in Walk:0.25 Walk:0.75; do STUDIO_ANIM=$t STUDIO_VIEWS="0,0.15,1;1,0.1,0.3" bash "$HERE/studio.sh" "${out}_rigged.glb" "${out}_${t/:/_}" 520 >/dev/null; done
  python3 -c "
from PIL import Image
a=Image.open('${out}_Walk_0.25_sheet.png');b=Image.open('${out}_Walk_0.75_sheet.png')
c=Image.new('RGB',(a.width+b.width,a.height));c.paste(a,(0,0));c.paste(b,(a.width,0));c.save('${out}_walk.png')"
  echo "check: ${out}_bones.png (bone colours) and ${out}_walk.png (walk poses)"
else
  sed -n 2,9p "$0"
fi
