#!/usr/bin/env bash
# Launches an installed or packaged Strata.app, checks it stays running, then quits it.
# Usage: scripts/smoke-test-app.sh <path to Strata.app>
set -euo pipefail

app="${1:?usage: smoke-test-app.sh <path to Strata.app>}"
binary="$app/Contents/MacOS/Strata"

test -x "$binary" || { echo "::error::$binary is missing or not executable"; exit 1; }
pkill -x Strata >/dev/null 2>&1 || true

"$binary" -StrataUITesting >/dev/null 2>&1 &
pid=$!
sleep 6
if ! kill -0 "$pid" 2>/dev/null; then
  echo "::error title=Smoke test::Strata exited within 6 seconds of launch"
  exit 1
fi
kill "$pid"
wait "$pid" 2>/dev/null || true
echo "Strata launched and stayed running."
