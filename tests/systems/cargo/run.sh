#!/usr/bin/env bash
# v11.63 (owner's freighter block): run the cargo test group (and the core smoke group) only - never the full suite.
#   tests/systems/dreadholm/run.sh [path-to-godot]
# The checks live in scripts/autotest.gd (_cargo, _smoke_core). Exit code 0 = all pass.
G="${1:-${GODOT:-godot}}"
cd "$(dirname "$0")/../../.." || exit 1
HL_CARGO=1 "$G" --headless --path . -- --autotest --quit-after-test 2>&1 | grep "^\[route\]" | grep -v "^\[route\] {\|step:"
exit "${PIPESTATUS[0]}"
