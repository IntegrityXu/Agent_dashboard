#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CORE="$ROOT/Packages/StatusBoardCore/Sources/StatusBoardCore"
mkdir -p "$ROOT/artifacts/probes/module-cache"
xcrun swiftc -swift-version 6 -module-cache-path "$ROOT/artifacts/probes/module-cache" \
  "$ROOT/Archive/LegacyIPC/DesktopFrameDecoder.swift" "$CORE/Domain.swift" "$CORE/AlertKind.swift" "$CORE/AgentActivity.swift" "$CORE/DesktopStream.swift" \
  "$ROOT/Archive/LegacyIPC/DesktopIPCProbe/main.swift" -o "$ROOT/artifacts/probes/DesktopIPCProbe"
