#!/bin/bash
# build_set.sh SET : build.py (light copies of names.json), mirror_x.py, shrink_tex.py 768 -> work/SET/final/NAME.glb, then four views -> work/SET/fimg
cd /home/claude/assetwork && export GODOT=/home/claude/godot/Godot_v4.3-stable_linux.x86_64 HL_REPO=/home/claude/homelancer-digital
python3 kit/build.py work/$1 work/$1/names.json > work/$1/build.log 2>&1
mkdir -p work/$1/final work/$1/fimg work/$1/mir
for f in $(python3 -c "import json;print(' '.join(v[0] for v in json.load(open('work/$1/names.json')).values()))"); do
  python3 kit/mirror_x.py work/$1/out/${f}_game.glb work/$1/mir/$f.glb >> work/$1/build.log 2>&1
  python3 kit/shrink_tex.py work/$1/mir/$f.glb work/$1/final/$f.glb 768 >> work/$1/build.log 2>&1
  VPX=300 xvfb-run -a $GODOT --path $HL_REPO --script tools/shipkit/views3.gd -- $PWD/work/$1/final/$f.glb $PWD/work/$1/fimg/$f > /dev/null 2>&1
done
