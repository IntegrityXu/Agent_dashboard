# Historical experiments

These sources are excluded from the application, Swift package and current validation commands.

- `LegacyIPC/`: the build-21477-only Swift/Python discovery observers and their retired full-frame decoder. Retained for historical protocol research, not for diagnosing current Codex. The archived build script is opt-in.
- `DesktopLens/`: the retired screen-capture/Metal lens and backdrop experiments, with the original Liquid-TUI MIT license and attribution. The current app uses native material and does not request screen-recording access.

Current checks: `scripts/test-core.sh`, `scripts/test-window-recovery.sh`, `scripts/package-app.sh`. Current IPC implementation: `Packages/StatusBoardCore/Sources/StatusBoardDesktop/DesktopSocket.swift` with `StatusBoardCore/DesktopMetadataDecoder.swift`.
