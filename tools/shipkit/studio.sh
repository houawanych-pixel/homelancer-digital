#!/bin/bash
# studio.sh in.glb /abs/out_prefix size
GP=$(mktemp -d); echo "config_version=5" > $GP/project.godot
S=${3:-400}
timeout 180 xvfb-run -a -s "-screen 0 1600x1200x24" /home/claude/godot/Godot_v4.3-stable_linux.x86_64 --audio-driver Dummy --rendering-driver opengl3 --resolution ${S}x${S} --path "$GP" --script "$(dirname "$0")/studio.gd" -- "$@" 2>&1 | grep -E "STUDIO|ERROR"
