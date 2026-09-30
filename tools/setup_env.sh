#!/bin/bash
# setup_env.sh — prepare a fresh Linux work session for Homelancer (Godot 4.3 + checks).
#   bash tools/setup_env.sh            editor/headless binary only (renders, route test, rigging tools)
#   bash tools/setup_env.sh --web      also the export templates (~1 GB download) for a local web build
# Installs to /home/claude/godot (override with GODOT_DIR). Afterwards: export GODOT=$GODOT_DIR/Godot_v4.3-stable_linux.x86_64
set -e
D="${GODOT_DIR:-/home/claude/godot}"; mkdir -p "$D"; cd "$D"
REL=https://github.com/godotengine/godot/releases/download/4.3-stable
if [ ! -x Godot_v4.3-stable_linux.x86_64 ]; then
  curl -sSL -o godot.zip $REL/Godot_v4.3-stable_linux.x86_64.zip && python3 -c "import zipfile;zipfile.ZipFile('godot.zip').extractall('.')" && rm godot.zip
  chmod +x Godot_v4.3-stable_linux.x86_64
fi
if [ "$1" = --web ] && [ ! -d ~/.local/share/godot/export_templates/4.3.stable ]; then
  curl -sSL -o tpl.tpz $REL/Godot_v4.3-stable_export_templates.tpz
  mkdir -p ~/.local/share/godot/export_templates
  python3 -c "import zipfile;zipfile.ZipFile('tpl.tpz').extractall('tpl')"
  mv tpl/templates ~/.local/share/godot/export_templates/4.3.stable && rm -rf tpl tpl.tpz
fi
"$D/Godot_v4.3-stable_linux.x86_64" --version
python3 -c "import numpy, PIL" 2>/dev/null && echo "numpy + Pillow OK" || echo "MISSING numpy/Pillow (pip install --break-system-packages numpy pillow)"
command -v xvfb-run >/dev/null && echo "xvfb-run OK" || echo "MISSING xvfb-run (needed for renders)"
echo "export GODOT=$D/Godot_v4.3-stable_linux.x86_64"
