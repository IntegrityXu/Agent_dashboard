# Idle history database recovery — build 35

Investigated October 24, 2026 (America/New_York).

## Evidence and cause

The user's observation was significant: Limited recovered only after sending a new message to Codex.

The build-34 diagnostic timeline and filesystem metadata showed:

| Local time | Evidence |
| --- | --- |
| 15:23:59 | History completion reads began failing with `sqlite_14`. The main history database's modification time was 15:23:59.616. |
| 15:24–15:31 | Completion reads continued retrying every five seconds, with throttled log entries each minute. No monitor restart or handshake loss was recorded. |
| 15:32:03 | A new turn began producing live stream updates. The history `-wal` and `-shm` files had creation timestamps of 15:32:03.958. |
| 15:32:05 | Completion reads recovered after 96 failed attempts spanning 485 seconds. |

This points to the history writer closing/checkpointing during inactivity, followed by recreating its WAL sidecars when new activity began. Past logs did not record the writer's internal close call, so the exact Codex pool/timer implementation is not claimed.

The failure mechanism was reproduced without touching Codex state. On this Mac, Apple SQLite **3.43.2** successfully opens a read-only handle to a cleanly closed WAL database, but the first query returns **SQLITE_CANTOPEN (14), system errno ENOENT (2)** when `-wal/-shm` are absent. A new writer makes the same query succeed. Holding a reader can preserve sidecars, but that does not solve a cold start when sidecars are already gone.

The synthetic writer uses SQLite's own normal shutdown with `SQLITE_FCNTL_PERSIST_WAL=0`; the test does not manually delete live sidecars or copy an active database. The [SQLite WAL lifecycle documentation](https://www.sqlite.org/walformat.html#file_lifecycles) explains the checkpoint/removal behavior. The [read-only WAL documentation](https://www.sqlite.org/wal.html#read_only_databases) describes sidecar requirements. A separate [macOS reproduction reported to Bun](https://github.com/oven-sh/bun/issues/45171) shows the same Apple/standard-library difference; our diagnosis rests on the local reproduction, not that report alone.

## Change

Production inventory, completion and agent-history readers now use a pinned **standard SQLite 3.54.1** C runtime instead of Apple SQLite. It is bundled and built for both application architectures; Homebrew is not a runtime dependency. Upstream source is unmodified, the official archive SHA3-256 was verified, public symbols are namespaced, and loadable extensions are disabled. Source provenance and regeneration instructions are in `Packages/StatusBoardCore/Sources/StatusBoardSQLite/vendor/README.md`.

The three readers share the same read-only connection setup. They still open with `SQLITE_OPEN_READONLY`, use normal SQLite locking, finalize statements and close connections after each bounded read. There is no read-write fallback, immutable/nolock URI, source-database copy or modification of Codex's journal mode. Standard SQLite may maintain normal coordination sidecars, while main database contents remain read-only.

Failure diagnostics now record the operation (open/prepare/step), SQLite/system error codes, and presence booleans for the database/WAL/SHM files. Paths, SQL, identities and conversation contents are excluded. Startup diagnostics record the bundled SQLite version.

## Validation

**146 Swift tests passed**, including six new regressions:

- Cold reads of completion, inventory and agent metadata after the Apple writer closes and sidecars disappear.
- Repeated writer idle/reopen cycles, with reads succeeding without any new prompt.
- Committed changes still present only in WAL are immediately visible; readers release locks so the writer can checkpoint.
- Production connections reject writes; missing databases are not created.
- Diagnostic records expose operation/file presence without paths or SQL.
- The session restores Done from idle history without any IPC traffic or new user activity.

Tests verify main-file bytes, modification time and inode stay unchanged after read-only recovery. **98 native AppKit assertions also passed**, including linking and running the app with the namespaced C runtime.

Local reproduction and logs are retained in `.build/sqlite-idle-validation/`. This is generated verification evidence, not an application dependency. A long post-delivery idle observation is distinct from the deterministic writer-close regressions above.

## Packaged application

The universal arm64/x86_64 Release build and strict ad-hoc signature verification passed. Final native regression rerun: **98 assertions passed**. The packaged application started at 15:44:06 with diagnostic `sqliteVersion: 3.54.1`, connected at 15:44:07 and reported all four features available, 11 verified live conversations, one processing task and current weekly quota. Normal resident execution was restored after the bounded diagnostic run.

Production data remains on the same Codex paths and in the same schema. The test fixture's main-file immutability checks and read-only rejection tests cover the access contract; long future idle periods have not been observed within this active turn.
