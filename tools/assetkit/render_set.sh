#!/bin/bash
# render_set.sh SET : top/side/3-4 views of every split piece of work/SET -> work/SET/view/cNN_*.png
cd /home/claude/assetwork/work/$1 && mkdir -p view
for f in prev/c*.glb; do n=$(basename $f .glb); VPX=300 xvfb-run -a /home/claude/godot/Godot_v4.3-stable_linux.x86_64 --path /home/claude/homelancer-digital --script tools/shipkit/views3.gd -- $PWD/$f $PWD/view/$n > /dev/null 2>&1; done
