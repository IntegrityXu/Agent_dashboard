# Build 33: audit fixes and source cleanup

## Behavior

- IPC consumes ready chunks in bounded batches (at most 16 reads / approximately 50 ms per batch) before expiry. Pending bytes or a partial frame receive a fixed 15-second grace. It is not renewed by subsequent bytes, so stalled or continuous input cannot defer timeouts forever.
- Quota decoding validates the selected response before committing. Malformed buckets/windows keep the prior quota and timestamp, log a source failure and retry after five seconds. Null/missing windows, unknown duration and a multi-bucket map without Codex are handled as legitimate absence; another bucket is never relabeled as Codex.
- A connected session with no successful quota read uses only its verified account's saved quota. A successful empty response replaces that cache (including persistence), preventing stale values from returning after restart.
- Stream removal has explicit reasons: untracked, unloaded, unavailable, invalid stream. Confirmed unload/untracking ends the stream warning and logs its reason; temporary loss retains the warning until a real recovery or end.

## Cleanup

- Removed duplicate `readInventory()` / `readRecovery()` entry points. Existing tests now exercise the production refresh functions.
- Split session source refreshes and receive scheduling into focused extensions, and split response/broadcast/stream handlers. Session coordinator reduced from 403 to 288 lines.
- Extracted app model, settings and aggregate diagnostic output from the entry-point file; updated Xcode and native-test source registration.
- Moved the obsolete full-frame decoder, build-21477-only IPC probes, retired desktop-lens/backdrop experiments and their scripts into `Archive/`. The lens archive retains the original MIT license. They are excluded from current builds/tests, with explicit historical-only documentation.
- Removed Python bytecode cache and added ignore rules. Existing build artifacts and historical evidence remain intact.

## Verification

- **130 Swift tests passed.** All four original audit reproductions pass. Additional tests cover receive batching, stalled partial headers, non-sliding grace expiry, malformed quota variants, null/absent quota, valid empty persistence, account isolation, and stream-warning lifecycle.
- **93 native UI assertions passed.** Tests cover window recovery, pinning, menus, compact/expanded behavior, animation, help, settings and quit. Tests use no production preferences or Codex monitoring.
- Static registration checks confirm every app source is registered once, no retired decoder remains in production sources, no duplicate legacy refresh entry point remains, and generated Python cache is absent from active probes.
- Universal Release build (Intel + Apple Silicon) and ad-hoc deep/strict signature validation passed.
- Replaced the running build 32 through its normal quit flow and launched build 33. Live UI confirmed Connected/Pinned, 1 processing, 0 waiting, 0 Done, root running, and freshly read weekly quota 30%. Restored the prior compact avatar presentation after verification.
- Automatic diagnostics confirm build-33 monitor startup and successful handshake at 15:00:50 EDT. No build-33 read failure or reconnect was recorded during the check.
- Logs: `.build/review-fixes-33/core-tests.log`, `native-tests.log`, `package.log`, `live-diagnostics.jsonl`.

The original disconnected screenshot still has no historical root-cause trace. These fixes address independently reproduced defects rather than claiming to reconstruct that unlogged event.
