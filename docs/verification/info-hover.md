# Info and hover interactions — build 29

Verified October 24, 2026 (America/New_York), version 0.2.1 build 29.

- Processing, Waiting for operation and Done no longer attach help text. Their existing Open Codex actions remain, and SwiftUI's link pointer style provides a pointing-hand cursor.
- Both the panel gear menu and menu-bar menu include Info. A native informational sheet shows the connection state, verified live/total conversation coverage, account and conversation scope, excluded legacy conversation count, source message and last complete sync time.
- Other panel help uses an app-local 0.35-second timer. Leaving the target, hiding its view, interacting with the panel, switching menus, sleeping or terminating cancels help. It neither changes system tooltip preferences nor takes keyboard focus.
- The four-row settings menu supports arrow/Tab navigation, Home/End and Return/Space activation. Repeated Info and overlapping Quit requests cannot stack dialogs.

## Evidence

`scripts/test-window-recovery.sh` passed **89 native assertions**, including 19 added checks for menu navigation, Info presentation/dismissal, compact-panel expansion, duplicate-dialog prevention, delayed help, cancellation, owner changes and focus preservation. Existing window recovery and quit checks still pass.

Reviewed the generated `info-dialog.png` and `design-cases/menu-dark.png` under `.build/window-recovery/`: dialog text and all four menu rows fit. The automated harness verifies native controller behavior; the pointing-hand appearance is configured through the system SwiftUI pointer API and was not independently observed through GUI automation.

`scripts/package-app.sh` completed the universal Release build and ad-hoc signature verification, replacing `dist/Status Board.app` with build 29. The previous app exited normally, and `scripts/run-app.sh` started the packaged build. The running process was confirmed at the exact `dist/Status Board.app` path (PID 45679 at verification). Native test and packaging logs are in `.build/interaction-validation/`.

The unchanged core's latest regression baseline remains **99 passing Swift tests** from build 28; these were not rerun for this UI-only update. Formal signing/notarization and the wider validation limitations in `results.md` remain outstanding.
