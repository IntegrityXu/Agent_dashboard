# Silent unread recovery — 0.2.1 build 6

The user reopened Codex while deliberately retaining an unread conversation. Connection recovered, but Done stayed at zero. The desktop listing confirmed that conversation was unread and `notLoaded`; its latest persisted turn was completed. The user specified that startup/reconnection must update counts without playing notification sounds.

## Source verification

For pinned Codex build 21477, the installed desktop implementation `V6` hashes JSON `["chatgpt", accountId, userId]`; local stdio host helper `xV` hashes `["local", "local", null]`. Desktop read-state `readForStartup` and `open` read `electron-thread-read-state-v1.unreadByIdentity[identityKey][executionHostKey]`. This is the desktop's actual scoped startup source, distinct from `legacyMigration`, which this implementation ignores. The authenticated helper principal matched the account/read account and the current store scope; the designated unread conversation was present in that local scope. No credentials, message bodies or raw store contents were logged.

## Behavior

- On startup and at five-second intervals (or promptly after read-store file changes), intersect scoped unread IDs with verified current-account local unarchived top-level inventory. Read only the latest turn's status and presence of a completion timestamp from the history database.
- Restore Done only for completed/unread candidates without a live observation. Live read, unread, active, waiting, failed and unknown observations take precedence and prevent duplicate contributions. Historical in-progress/failed/interrupted rows do not fabricate current processing or waiting counts.
- Recovery changes aggregate snapshots only. It never emits completion transitions or invokes an audio path. Current audio remains disabled as previously requested.
- Account/user changes retire the entire session. Unsupported store schema and failed verification fail closed. Remote-host, other-user/account, legacy migration and archived/child entries do not become recovered Done contributions.
- Live coverage remains the number of real live observations; recovered Done does not claim full runtime coverage or advance complete-sync timestamps.

## Validation

46 Swift tests passed, including five new recovery tests: principal/account/expiry validation; user/host/legacy isolation; latest terminal-turn filtering; unloaded recovery with live precedence and silent baseline transitions; and atomic read-store changes removing recovered unread without loading a stream. Build and live validation evidence are recorded in `artifacts/app-validation/unloaded-unread-*`.

Release build and strict signature verification passed. On 2026-10-23 at 23:06:48 America/New_York, the packaged app reported Connected, processing 1, waiting 0, Done 1, restoredDone 1 and live coverage 1/68. Its rendered panel showed the same counts. An independent desktop listing still reported the designated conversation as `notLoaded` and unread. No conversation was opened, resumed, marked read, or sent a test prompt; recovery used startup data and no sound was played. After verification the panel was restarted normally without ongoing diagnostics.

This remains a pinned private-desktop adapter. The scoped store and read-only history projection extend startup Done coverage; they do not establish full-account live runtime or waiting-state coverage.
