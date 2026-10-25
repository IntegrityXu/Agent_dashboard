#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/artifacts/probes/StatusBoardFocusProbe.app"
mkdir -p "$APP/Contents/MacOS" "$ROOT/artifacts/probes/module-cache"
xcrun swiftc -swift-version 6 -module-cache-path "$ROOT/artifacts/probes/module-cache" \
  "$ROOT/Probes/FocusProbe/main.swift" -o "$APP/Contents/MacOS/StatusBoardFocusProbe"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>StatusBoardFocusProbe</string>
<key>CFBundleIdentifier</key><string>local.statusboard.focusprobe</string>
<key>CFBundleName</key><string>Status Board Focus Probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSFocusStatusUsageDescription</key><string>Test whether shared Focus status can suppress Status Board sounds.</string>
<key>NSUserActivityTypes</key><array><string>INSendMessageIntent</string></array>
</dict></plist>
PLIST
# An ad-hoc capability declaration is only a local feasibility experiment;
# successful signing does not qualify provisioning or release entitlement access.
codesign --force --sign - --entitlements "$ROOT/Probes/FocusProbe/FocusProbe.entitlements" "$APP"
