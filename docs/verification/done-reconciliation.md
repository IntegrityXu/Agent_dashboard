# Done read-state reconciliation — 0.2.1 build 4

The user reported Done = 1 with no unread results when opening the panel; starting a new turn changed it to processing = 1, Done = 0. After that new turn had started, all five loaded conversations' fresh owner snapshots agreed with the app listing: four completed/read and the current conversation active/read. The original stale frame was no longer available, so its exact timing cannot be reconstructed.

The existing observer relied on a change to the persisted read-store digest to refresh silent read updates. Owner discovery does not refresh an unchanged owner. A missed notification, or an unread/read round trip coalesced into the same persisted digest, could therefore leave an old Done contribution indefinitely. Opening the already-running single-instance app also reused that state.

## Change

The monitor now re-fetches an authoritative owner snapshot for each completed/unread contribution after one second, then every five seconds while it remains unread. It stops checking that item when read, active, unknown, or removed. In-flight snapshots are not duplicated or given an extended timeout by read-store events. Neither elapsed time nor foreground-window detection changes the unread value. Same-revision snapshots remain silent and can update read state; a genuine unread result continues to count.

This uses the existing version-gated read-only subscription and current-account inventory. It does not read message bodies from files, write Codex state, change UI layout, enable Focus, or enable audio. IPC snapshots can contain history temporarily; the existing metadata allowlist discards message content. Five-second rechecks are limited to Done contributors to avoid polling all conversation history.

## Evidence and limits

- 39 Swift tests pass, including two new regressions covering no file notification, unchanged revision, genuine unread retention, pending request handling, new runs, unavailable state, and removal.
- On the authorized disposable conversation, a foreground completion produced unread=true at revision 114, then an owner snapshot returned unread=false at the **same revision**. The original invalidation path worked in this trial; this does not claim to reproduce the user's exact missed event.
- The freshly packaged application starts with Done=0, processing=1 while this implementation conversation is active. All five loaded streams were covered after startup. Aggregate evidence is in `artifacts/app-validation/done-reconciliation-live.jsonl`; no conversation contents are logged.
- A second real test completed while unread: both the Codex listing and a fresh owner snapshot reported unread=true, and the new panel retained Done=1 through repeated checks. After the user confirmed reading, both Codex and the panel reported read / Done=0. This verifies real unread retention and read clearing in the packaged application; notification-loss recovery is covered by the regression test above.
- Release build and ad-hoc signature verification pass. Global account coverage, long-running performance, Focus/audio, and full release qualification remain as previously documented.
