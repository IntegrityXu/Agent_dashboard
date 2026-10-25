# Build 8: logic fixes and structure

Validated October 23, 2026 (America/New_York). Version 0.2.1 build 8, adapter pinned to Codex build 21477.

## Five fixes

1. **Incomplete canonical history:** runtime and blocking flags remain available without inventing the latest turn. An uncovered tail or missing newest entity cannot expose an older completion. Streams awaiting snapshots or recovering from revision gaps block disk fallback. Discovery timeouts also block fallback until an owner is found or discovery reports `no-client-found`.
2. **Inventory truncation:** all eligible local, unarchived, top-level account conversations participate in recovery. The former 512 limit is removed. Owner discovery still has at most eight outstanding requests, and subsequent cycles append work without replacing the unprocessed tail.
3. **Reconnect delay:** a session that completed the desktop handshake and quota read resets retry delay to one second, including when the session later throws. Consecutive failed attempts use 1, 2, 4, 8, then 15 seconds. Failed sessions release their socket before waiting.
4. **Expired presentation:** the three-second failure grace also requires the original live snapshot to remain within its ten-second freshness window. Failure cannot revive expired counts or Connected status.
5. **Heartbeat consistency:** completed unread heartbeat tasks count toward Done through both restored and live sources. Alert suppression remains separate: heartbeat transitions and all startup/reconnect snapshots still produce no alert candidates. Audio playback remains deferred and unwired.

## Production structure

- `DesktopMonitor`: worker ownership, cancellation, reconnect, helper lifecycle.
- `VerifiedIdentity`: one account/scope verification and fingerprint implementation. The session reuses the initial verification, then checks every 15 seconds.
- `DesktopSession`: transport orchestration, periodic reads, published snapshots.
- `ThreadTracking`: shared owner/stream/deadline cleanup and recovery exclusion.
- `DiscoveryQueue` / `ReconnectBackoff`: bounded scheduling and retry policy, independently tested.
- `ReadStoreInvalidator`: each refresh returns the parsed state and change decision from the same file read. Event-driven and periodic refreshes share `readRecovery`.
- `LiveClassification` / `StoredCompletions`: live classification and conservative unloaded completion recovery. `DashboardPresentation` owns visible freshness and saved quota.

The existing `TaskReducer`, `SnapshotStore`, and `AlertGate` are retained as tested full-spec contracts; the desktop preview does not run them as a second state pipeline. They must not be wired alongside the production aggregation without reconciling their contracts. The app/UI source is unchanged.

## Verification

- `scripts/test-core.sh`: **57 tests passed**. Nine added regressions cover missing history/runtime precedence, a missing newest entity, 513 eligible conversations, retry reset, expired failure grace, heartbeat source agreement, discovery fairness, cleanup, and failed discovery semantics. Existing silent bootstrap, heartbeat suppression, read-clearing, account isolation and stream revision tests remain green.
- `scripts/package-app.sh`: Release build succeeded and packaged the ad-hoc-signed app. Strict signature verification passed separately. Bundle version is 8.
- Live startup smoke: after restarting Status Board, the first aggregate snapshot was connecting; the next was connected with processing 1, waiting 0, Done 0. The sampled run remained connected through the first periodic identity/owner refresh. This is startup evidence, not a new full Codex quit/reopen test.
- Live coverage in this sample: 3 of 70 account-assigned conversations, with 56 unloaded completed conversations restored and 29 unassigned records excluded. Partial coverage remains explicit; this does not establish complete account runtime coverage.
- `StatusBoard/App/StatusBoardApp.swift` SHA-256 remains `cf1e011e0692ee18a73328002004d8f4f53ae7ec4780f3012f4ba415051a24d7`. A rendered live panel was inspected. No layout, interaction, or preference code changed.
- Temporary aggregate diagnostics were stopped; Status Board was relaunched normally. No prompts were sent to other conversations and no read/unread state was changed for testing.

Local evidence: `artifacts/app-validation/review-fixes-tests.txt`, `review-fixes-package.txt`, `review-fixes-live.jsonl`, `review-fixes-preview.png`. The original defect reproductions remain in `review-repro-results.txt`.

Remaining limits: private protocol compatibility, partial live coverage, full restart/account-switch/fault matrices, and large-inventory performance qualification. No audio or Focus work is included in this build.
