#!/bin/bash
# render6.sh SET [glob] : six views of each split piece -> work/SET/v6, sheet -> work/SET/sheet6.jpg
cd /home/claude/assetwork/work/$1 && mkdir -p v6
for f in prev/${2:-c*}.glb; do n=$(basename $f .glb); VPX=300 xvfb-run -a /home/claude/godot/Godot_v4.3-stable_linux.x86_64 --path /home/claude/homelancer-digital --script tools/shipkit/views6.gd -- $PWD/$f $PWD/v6/$n > /dev/null 2>&1; done
python3 /home/claude/assetwork/kit/sheet6.py . sheet6.jpg
