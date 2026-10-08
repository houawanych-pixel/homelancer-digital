#!/bin/bash
# orient_set.sh SET "N[:ops] N[:ops] ..." : orient.py on the listed pieces of work/SET, then four views of each -> work/SET/oimg
cd /home/claude/assetwork/work/$1 && mkdir -p ori oimg
for it in $2; do n=$(printf "%02d" ${it%%:*}); ops=""; [[ $it == *:* ]] && ops=${it#*:}
  python3 ../../kit/orient.py prev/c$n.glb ori/c$n.glb $ops > ori/c$n.log 2>&1
  VPX=300 xvfb-run -a /home/claude/godot/Godot_v4.3-stable_linux.x86_64 --path /home/claude/homelancer-digital --script tools/shipkit/views3.gd -- $PWD/ori/c$n.glb $PWD/oimg/c$n > /dev/null 2>&1
done
