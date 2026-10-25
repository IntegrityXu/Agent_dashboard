# Build 12 — covered-panel recovery

Checked October 24, 2026. User authorized repairing Show Status Board and adding menu-bar Pin/Unpin.

## Behavior

- Show Status Board waits for the menu tracking loop to finish, expands the panel, activates the app and brings the panel forward at floating level. It preserves the persistent pin preference.
- Temporary reveal survives key resignation, menu dismissal and data/layout refresh. An outside mouse click or activation of another app restores an unpinned panel to desktop level. Pinned panels stay floating. Delayed activation notifications are ignored when their app is no longer the foreground app.
- The menu action reads Pin Status Board or Unpin Status Board, synchronized with the panel button. Either menu action reveals the expanded panel. Unpin leaves it temporarily reachable until the next outside interaction. Pin state persists normally.
- Background events never invoke reveal. The panel's existing Spaces/Mission Control collection behavior is unchanged.

## Evidence

- `scripts/test-core.sh`: 84 tests pass; task/audio regressions remain green.
- `scripts/test-window-recovery.sh`: 26 native assertions pass. The probe compiles the actual app source with only its entry point removed and runs in its own preference domain, without DesktopMonitor or Codex requests.
- Checks cover menu target/action dispatch, deferred reveal, key-resignation survival, layout/data refresh, stale activation notifications, direct Pin/Unpin, preference writes, panel/menu synchronization and outside-interaction handling. WindowServer reports the revealed panel at level 3 ahead of a covering ordinary window at level 0. A real activation of the previously foreground app ends temporary reveal and restores desktop level.
- The WindowServer assertion waits for the event loop to flush native window ordering; an immediate same-stack read during the initial probe observed stale ordering. The settled check passes.
- Universal Release package builds and strict ad-hoc signature verification succeeds. Output: `dist/Status Board.app`, version 0.2.1 build 12.

Logs: `artifacts/app-validation/window-recovery-core.txt`, `window-recovery-native.txt` and `window-recovery-build.txt`.

## Limits

The probe drives the real menu actions but invokes menu tracking delegate callbacks directly; it does not simulate physical mouse selection in the menu bar. The outside-click handler is exercised directly; real app switching is exercised through NSWorkspace. Physical menu clicking/global mouse delivery and the broader fullscreen/Spaces/multi-display matrix still need user/native acceptance. This report does not claim Mission Control selection was repaired.
