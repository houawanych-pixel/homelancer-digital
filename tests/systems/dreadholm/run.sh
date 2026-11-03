#!/usr/bin/env bash
# v11.57 (owner's Dreadholm update): run the Dreadholm test group (and the core smoke group) only - never the full suite.
#   tests/systems/dreadholm/run.sh [path-to-godot]
# The checks live in scripts/autotest.gd (_dreadholm, _smoke_core, _job_v1145). Exit code 0 = all pass.
G="${1:-${GODOT:-godot}}"
cd "$(dirname "$0")/../../.." || exit 1
HL_DREADHOLM=1 "$G" --headless --path . -- --autotest --quit-after-test 2>&1 | grep "^\[route\]" | grep -v "^\[route\] {\|step:"
exit "${PIPESTATUS[0]}"
