# Build 9: owner discovery and read refresh timing

October 23, 2026 (America/New_York). Version 0.2.1 build 9; Codex adapter remains pinned to build 21477.

## Owner discovery

The pinned router permits 10 seconds for client discovery before forwarding a request. The observer's 3-second forwarded timeout does not include that discovery stage. The local deadline is now 15 seconds (10 + 3 + 2 seconds of margin); initialization retains its 5-second deadline. Buffered responses are consumed before timeout cleanup.

Discovery timeout alone no longer removes a never-loaded conversation's verified disk completion/read coverage. Previously live streams still block older disk completion data when their source becomes unavailable. A timed-out request ID is retained for at most 30 seconds to accept a late result, but a newer request or thread removal invalidates it. Late replies cannot overwrite newer discovery or revive removed threads. Session replacement clears all pending state.

## Read changes during snapshots

Read-store changes now leave a pending refresh flag when an owner snapshot is already in flight. The accepted snapshot clears its deadline and triggers one additional snapshot when that flag is set. Multiple changes coalesce, and the original timeout is not extended. Both read → unread and unread → read converge to the latest owner state.

Older-revision snapshots do not consume the pending refresh. Owner replacement, snapshot timeout, and removal clear the previous owner's flag; the new subscription establishes its own baseline. Snapshot refreshes continue to use the existing silent snapshot path, without replaying alert candidates.

## Regression evidence

Ten deterministic session tests were added in `SessionTimingTests.swift`. They exercise the actual coordinator, file reader, SQLite completion reader, projection, and stream handler using temporary stores, a fake transport and a controllable monotonic clock. Tests create no real Codex sockets, processes or conversations.

- Slow discovery beyond the former five-second limit preserves Done.
- Buffered replies are handled before cleanup; genuinely late replies can establish a baseline or restore unloaded coverage.
- Newer discovery, removal, and the 30-second retention boundary reject obsolete replies.
- Known-live timeouts continue to exclude stale completion data.
- Read/unread changes during an in-flight snapshot get a follow-up, including several coalesced changes.
- Older revisions and old owners cannot satisfy the current snapshot request; timeout cleans up pending refresh state.

The initial regression run reproduced the failures before the fixes (`build9-tests-before.txt`). After repair, **67 tests passed**, including all existing silent bootstrap/reconnect and heartbeat suppression tests (`build9-tests.txt`). Release packaging and strict signature verification passed (`build9-package.txt`).

The UI source is unchanged: `StatusBoard/App/StatusBoardApp.swift` SHA-256 remains `cf1e011e0692ee18a73328002004d8f4f53ae7ec4780f3012f4ba415051a24d7`. Audio playback and Focus remain deferred. No login or sound preferences were changed.

Live startup evidence and its limits are recorded in `artifacts/app-validation/build9-summary.json`, with aggregate-only snapshots in `build9-live.jsonl` and the inspected panel in `build9-preview.png`. This smoke check restarts Status Board, not Codex, and does not claim a complete quit/reopen or account-switch matrix.
