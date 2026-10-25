# Review fixes and cleanup

Verified October 24, 2026 (America/New_York), on the source following build 27.

## Corrections

- The incremental metadata decoder supports `value` before `path` when replacing the entire canonical `entitiesByKey` map. Dynamic keys, including `text`, `questions`, and `entitiesByKey`, survive all six patch-field permutations. Candidates remain subject to the existing metadata budget and exact stream projection. Ordinary message text, prompts, and question text are discarded during decoding.
- `VerifiedIdentity.fingerprint` hashes length-prefixed backend, workspace, and authenticated-user-scope components with full SHA-256. Switching users within one workspace immediately invalidates the previous live presentation and prevents reuse of another user's saved usage. Component concatenation cannot alias distinct principals.
- Audio events are checked for freshness both on receipt and immediately before playback. Events older than ten seconds are skipped but remain consumed. Fresh subsequent events still play; the existing inclusive ten-second boundary, mute, reconnect, and cancellation behavior remains covered.

Compatibility: saved usage created by the old workspace-only fingerprint will remain hidden until a fresh verified quota read writes a user-scoped cache. Old caches cannot safely be attributed to an individual user. No credential is persisted.

## Cleanup and simplification

Removed production-unreferenced `TaskReducer`, `TaskRecord`, `ReadState`, `AccountKey`, `QuotaSnapshot`, `SnapshotStore`, `AlertGate`, and its prototype event/Focus types. Retained the used `AlertKind` in its own file. Removed the unused `BoardModel.refresh`, `TaskCounts.showsWaitingBadge`, and production-unused `DesktopFailure.protocolError` member; database fixtures now use the existing unavailable error.

The 13 tests specific to those abandoned contracts were removed. Existing runtime classification, inventory/account filtering, unread recovery, presentation, stream, and audio tests remain. Six new tests cover field permutations, decoder privacy, decoder memory bounds, same-workspace identity changes, queued-event expiry/replay, and the age boundary.

`DesktopObservation.isWaitingForUser` centralizes the shared pending-request/active-flag rule. Agent traversal delegates source selection and state selection to small functions, preserving existing precedence. Window control stays in `StatusBoardApp.swift` (501 lines); SwiftUI/drag controls and optional visual/audio preview support are in `BoardView.swift` and `PreviewSupport.swift`. Layout and interaction code were moved without behavioral changes.

Historical probes remain separate. `DesktopFrameDecoder` is retained because the desktop IPC probe still uses it. The probe build now references `AlertKind.swift`. The native test script compiles all current app source files and links only object files listed by SwiftPM's current output maps, so stale objects from removed sources cannot reintroduce deleted code.

## Verification

- Before the fixes, the newly added defect tests reproduced lost map data, shared-user fingerprints/previous-user presentation, and playback of expired queued sounds.
- `scripts/test-core.sh`: **99 tests passed**. The count is the former 106 minus 13 obsolete-contract tests plus 6 regression tests. Parameterized map coverage includes four key shapes and all six field orders.
- `scripts/test-window-recovery.sh`: **70 native assertions passed**, including window/menu recovery, animation, compact status, agent rows, and quit confirmation. Inspected the generated agent-panel image; layout remains intact.
- `scripts/build-app.sh Release`: **BUILD SUCCEEDED**, universal x86_64 and arm64 executable. The only reported warning was skipped App Intents metadata extraction because the app does not use AppIntents.
- `bash scripts/build-desktop-probe.sh`: passed; the probe was compiled, not connected to a live account.
- Shell syntax checks and source/script reference search passed for removed symbols and filenames.

The first sandboxed Xcode run could not write system caches; the first sandboxed native UI run could not connect to the window service and was stopped. Reruns with the required local access succeeded. Logs are in `.build/code-review/`.

Real account switching and extended live-session soak testing were not performed. These results verify deterministic regressions, native UI behavior, and compilation; they do not establish compatibility beyond the existing pinned Codex build. The initial source review did not repackage the distribution bundle; the subsequent packaging and startup verification is recorded below.


## Build 28 packaging and live startup

Completed October 24, 2026 (America/New_York), at the user's request. Version remains 0.2.1; CFBundleVersion is now 28 to distinguish the repaired executable.

- Normally terminated the previous Status Board process before replacing its bundle. Codex itself was not terminated.
- `scripts/package-app.sh` succeeded. The fresh universal Release bundle was ad-hoc signed and verified with `codesign --verify --deep --strict`, then installed at `dist/Status Board.app`.
- Verified packaged build number 28 and both x86_64/arm64 slices.
- Launched that exact bundle with aggregate-only diagnostics, a panel render, and a 25-second automatic quit. Collected 24 samples: one initializing sample followed by 23 connected samples, with zero disconnections after readiness. The final sample showed processing 1, waiting 0, done 0, one running agent row, and weekly remaining 42%. Live coverage was 6/72; the existing partial-coverage limitation remains.
- Inspected the actual rendered panel: quota, counts, agent row, Connected footer, and saved pin state displayed correctly.
- Confirmed the timed run exited normally, then relaunched the bundle without diagnostic/test arguments for ordinary use.

Evidence: `.build/release-validation/package.log`, `live.jsonl`, and `live-panel.png`. This short live startup check supplements the 99 Swift tests and 70 native assertions; it does not replace extended soak testing or real multi-user account-switch acceptance.
