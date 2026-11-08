#!/bin/bash
# v12.84 build_mechs.sh — the split Tripo mechs (tools/tripo_import.py --kind mech) -> rigged game mechs.
#   build_mechs.sh ITEMS_DIR WORK_DIR [name ...]
# For each HL_MECH_*.glb: reduce to ~24k tris with 1024 px textures (rig_mech.sh look), guess the joints
# (guess_joints.py; --arms-down for mechs whose gun arms hang outside the legs), rig with the 22-bone humanoid
# (Idle + Walk) and write WORK/<name>_rigged.glb plus the bone / walk pictures to check.
# Then tools/mechkit/install_mechs.py copies them into assets/mech_frames and bakes the .scn (mech_bake.gd).
set -e
K="$(cd "$(dirname "$0")/../shipkit" && pwd)"
items=$(realpath "$1"); work=$(realpath -m "$2"); shift 2
mkdir -p "$work"
names="$*"; [ -z "$names" ] && names=$(cd "$items" && ls HL_MECH_*.glb | sed 's/\.glb$//')
for n in $names; do
  [ -f "$work/${n}_rigged.glb" ] && { echo "skip $n"; continue; }
  TRIS=${TRIS:-24000} TEX=${TEX:-1024} bash "$K/rig_mech.sh" look "$items/$n.glb" "$work/$n" >/dev/null 2>&1
  case "$n" in *Lineup*) AD=--arms-down ;; *) AD= ;; esac
  python3 "$K/guess_joints.py" "$work/${n}_body.glb" "$work/${n}_guess.json" $AD >/dev/null
  bash "$K/rig_mech.sh" rig "$work/$n" "$work/${n}_guess.json" >/dev/null 2>&1
  echo "done $n"
done
