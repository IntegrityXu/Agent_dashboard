#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/artifacts/preflight"
mkdir -p "$OUT/module-cache"
sw_vers
uname -m
for key in hw.optional.arm64 sysctl.proc_translated machdep.cpu.brand_string; do
  sysctl -n "$key" || true
done
xcode-select -p
xcodebuild -version
xcrun swift --version
SDK="$(xcrun --sdk macosx --show-sdk-path)"
echo "SDK: $SDK"
cat > "$OUT/smoke.swift" <<'SWIFT'
import Foundation
print("Foundation smoke PASS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
SWIFT
xcrun swiftc -swift-version 6 -sdk "$SDK" -module-cache-path "$OUT/module-cache" "$OUT/smoke.swift" -o "$OUT/smoke"
"$OUT/smoke"
