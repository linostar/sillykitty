#!/usr/bin/env bash
# Validation gate: asset import, project check (movement-only restriction +
# strict script compile), headless gameplay tests, headless run of the main
# scene. Exits non-zero on the first failure and points at the log that
# explains it. Every Godot call is killed after GODOT_TIMEOUT seconds.
# Env: GODOT (Godot binary), GODOT_TIMEOUT (default 300), RUN_FRAMES (headless run length, default 300).
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
GODOT_TIMEOUT="${GODOT_TIMEOUT:-300}"
LOG_DIR=build/logs
mkdir -p "$LOG_DIR"

fail() {
  echo "FAIL $1 (log: $2)" >&2
  grep -E "ERROR|WARNING|check_project|test_gameplay" "$2" >&2 || true
  exit 1
}

# Runs Godot with a hard timeout (macOS has no coreutils `timeout`; perl's alarm
# kills the process with SIGALRM, exit status 142). Usage: godot <log> <args...>
godot() {
  local log="$1"
  shift
  local status=0
  perl -e 'alarm shift @ARGV; exec @ARGV or die "exec failed: $!\n"' "$GODOT_TIMEOUT" "$GODOT" "$@" >"$log" 2>&1 || status=$?
  if [ "$status" -eq 142 ]; then
    echo "ERROR: timed out after ${GODOT_TIMEOUT}s" >>"$log"
  fi
  return "$status"
}

godot "$LOG_DIR/import.log" --headless --path sillykitty --import || fail "import exited non-zero" "$LOG_DIR/import.log"
if grep -qE "ERROR|WARNING" "$LOG_DIR/import.log"; then fail "import reported problems" "$LOG_DIR/import.log"; fi

# Godot exits 0 even when a --script fails to compile, so the explicit OK line
# is the only trustworthy success signal for script runs.
godot "$LOG_DIR/check.log" --headless --path sillykitty --script "$PWD/tools/check_project.gd" || true
if ! grep -q "^check_project: OK" "$LOG_DIR/check.log" || grep -qE "ERROR|WARNING" "$LOG_DIR/check.log"; then
  fail "project check" "$LOG_DIR/check.log"
fi

godot "$LOG_DIR/test.log" --headless --path sillykitty --fixed-fps 60 --script "$PWD/tools/test_gameplay.gd" || true
if ! grep -q "^test_gameplay: OK" "$LOG_DIR/test.log" || grep -qE "ERROR|WARNING" "$LOG_DIR/test.log"; then
  fail "gameplay tests" "$LOG_DIR/test.log"
fi

godot "$LOG_DIR/run.log" --headless --path sillykitty --quit-after "${RUN_FRAMES:-300}" || fail "headless run exited non-zero" "$LOG_DIR/run.log"
if grep -qE "ERROR|WARNING" "$LOG_DIR/run.log"; then fail "headless run reported problems" "$LOG_DIR/run.log"; fi

echo "PASS validate ($(grep "^check_project: OK" "$LOG_DIR/check.log"); $(grep "^test_gameplay: OK" "$LOG_DIR/test.log"))"
