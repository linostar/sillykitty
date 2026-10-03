#!/usr/bin/env bash
# Validation gate: asset import, project check (movement-only restriction +
# strict script compile), headless run of the main scene. Exits non-zero on
# the first failure and points at the log that explains it.
# Env: GODOT (Godot binary), RUN_FRAMES (headless run length, default 300).
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
LOG_DIR=build/logs
mkdir -p "$LOG_DIR"

fail() {
  echo "FAIL $1 (log: $2)" >&2
  grep -E "ERROR|WARNING|check_project" "$2" >&2 || true
  exit 1
}

"$GODOT" --headless --path sillykitty --import >"$LOG_DIR/import.log" 2>&1 || fail "import exited non-zero" "$LOG_DIR/import.log"
if grep -qE "ERROR|WARNING" "$LOG_DIR/import.log"; then fail "import reported problems" "$LOG_DIR/import.log"; fi

# Godot exits 0 even when the checker script itself fails to compile, so the
# explicit OK line is the only trustworthy success signal.
"$GODOT" --headless --path sillykitty --script "$PWD/tools/check_project.gd" >"$LOG_DIR/check.log" 2>&1 || true
if ! grep -q "^check_project: OK" "$LOG_DIR/check.log" || grep -qE "ERROR|WARNING" "$LOG_DIR/check.log"; then
  fail "project check" "$LOG_DIR/check.log"
fi

"$GODOT" --headless --path sillykitty --quit-after "${RUN_FRAMES:-300}" >"$LOG_DIR/run.log" 2>&1 || fail "headless run exited non-zero" "$LOG_DIR/run.log"
if grep -qE "ERROR|WARNING" "$LOG_DIR/run.log"; then fail "headless run reported problems" "$LOG_DIR/run.log"; fi

echo "PASS validate ($(grep "^check_project: OK" "$LOG_DIR/check.log"))"
