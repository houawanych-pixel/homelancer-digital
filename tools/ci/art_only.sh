#!/usr/bin/env bash
# Nov 2 2026 (owner): is this push art only (rooms, clips, images, docs)? Prints true / false.
# usage: tools/ci/art_only.sh <before-sha> <after-sha>
before="$1"; after="$2"
if [ -z "$before" ] || [ "$before" = "0000000000000000000000000000000000000000" ] || ! git cat-file -e "$before" 2>/dev/null; then echo false; exit 0; fi
files=$(git diff --name-only "$before" "$after")
[ -z "$files" ] && { echo true; exit 0; }
code=$(echo "$files" | grep -vE '^(assets|art|docs)/|\.(png|jpe?g|webp|ogv|ogg|mp3|mp4|wav|glb|gltf|import|md|txt)$' || true)
[ -z "$code" ] && echo true || echo false
