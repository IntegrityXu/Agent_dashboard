#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# TCC must see the application bundle through Launch Services. Invoking the
# Mach-O directly from another app can attribute the privacy request to its
# responsible process and abort even though our bundle has the usage key.
open -n "$ROOT/artifacts/probes/StatusBoardNativeProbe.app" \
  --stdout "$ROOT/artifacts/preflight/native-launchservices.txt" \
  --stderr "$ROOT/artifacts/preflight/native-launchservices-errors.txt" \
  --args --interactive
