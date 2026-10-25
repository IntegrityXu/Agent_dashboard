#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/artifacts/probes"
mkdir -p "$OUT/module-cache"
xcrun swiftc -swift-version 6 -module-cache-path "$OUT/module-cache" \
  "$ROOT/Probes/CodexProbe/main.swift" -o "$OUT/CodexProbe"
APP="$OUT/StatusBoardNativeProbe.app"
mkdir -p "$APP/Contents/MacOS"
xcrun swiftc -swift-version 6 -module-cache-path "$OUT/module-cache" \
  "$ROOT/Probes/NativeProbe/main.swift" -o "$APP/Contents/MacOS/StatusBoardNativeProbe"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>StatusBoardNativeProbe</string>
<key>CFBundleIdentifier</key><string>local.statusboard.nativeprobe</string>
<key>CFBundleName</key><string>Status Board Native Probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSFocusStatusUsageDescription</key><string>Validate whether Focus status can suppress Status Board sounds.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "$APP"
