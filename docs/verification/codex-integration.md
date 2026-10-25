# Codex source discovery

> Historical source investigation, superseded for delivery status by [the build 7 progress index](results.md). The version-pinned observer is integrated in the preview; builds 6–7 also recover scoped local completed/read and unread contributions. See [integration history](usable-preview.md), [unloaded recovery](unloaded-unread.md) and [build 7](read-clears-done.md). Exploratory limitations below describe that earlier checkpoint; complete live runtime/remote/cloud coverage and durable event qualification remain open.

Observed October 23, 2026 on the environment in [environment.md](environment.md). Installed source: Codex CLI 0.163.0-alpha.11.2. These observations do not qualify a production adapter. The experimental desktop runtime candidate below now has a working Swift implementation.

## Verified interface observations

The installed normal and experimental JSON schemas were generated into ignored `artifacts/protocol/`. Experimental output was needed specifically to inspect unread state and account scope. The read-only Swift probe uses JSONL framing, request IDs, a five-second request timeout and 25-second overall deadline. Its allowlist contains only initialization and account/thread reads. It kills only the helper it owns, redacts all response bodies, and does not send prompts, approvals, resumes, read-state updates or account mutations. `thread/list` uses `useStateDbOnly: true` to avoid the default scan-and-repair operation.

| Contract | Observed mapping / limitation |
| --- | --- |
| Account identity | Experimental `account/read.workspaceRouting.chatgptAccountId` and `backendOrigin`; real response contained workspace identity |
| Quota | `account/rateLimits/read.accountId`, `rateLimitsByLimitId`, primary/secondary windows with `usedPercent`, optional `windowDurationMins` and `resetsAt`; real read succeeded, one bucket |
| Task list | `thread/list.data`, `nextCursor`; 100 rows on the sampled page, another page present |
| Source filters | Omitted/empty `sourceKinds` defaults to interactive sources. Probe explicitly lists all schema enum values; an empty provider filter means all providers |
| Subagents | `parentThreadId` identifies subagents; `forkedFromId` must not be used as that test |
| Durable unread | Experimental `thread/list.readStates[threadId]` and `thread/read.readState`; a missing key means ineligible, not read |
| Read semantics | `firstUnread` is the earliest unread position, potentially `threadStart` or an older turn. A per-current-run mapping still needs proof |
| Read revisions | Opaque strings; not numeric event sequence numbers |
| Runtime state | Sampled standalone server returned `notLoaded` for every one of the 100 listed rows, and zero loaded threads |
| Notifications | Schema contains `thread/readState/changed`; field existence alone proves neither desktop delivery nor a replay boundary |

The standalone probe returned 45 eligible read receipts for its 100-row sample. It does not prove the remaining rows are read, that all desktop threads are covered, or that a fresh server observes desktop runtime activity.

## Connection decision

`codex app-server proxy` tried the documented default control socket and reported that it did not exist. A read-only process inventory found the running app-server processes with no published socket listener (one explicitly used `stdio://`). No guessed socket was attached, and no desktop process was restarted or reconfigured.

Decision: reject the **standalone app-server as the sole production source** for now. Keep it as a verified candidate for quota/account reads. At this first checkpoint G2 and G4 were blocked on selecting and proving a desktop observation source; the later IPC experiment below resolves per-thread transport access, but not complete scope; do not replace `notLoaded` with idle or zero.

## User-authorized real desktop experiment

The user explicitly authorized one disposable test conversation. It asked a test-only question, received an authorized test follow-up, and completed. The user then opened the result and confirmed it was read. No other conversation was modified. The test conversation remains available and was not archived or deleted.

Observed independently:

1. Desktop status API: active/in-progress, then idle/completed. The asynchronous question while the agent continued waiting did **not** establish `waitingOnUserInput`; ordinary waiting remains unverified.
2. Read-only `thread_history_1.sqlite.thread_turns`: the designated turn changed from `inProgress` to `completed`.
3. Desktop inventory: `isUnread` was true after completion and false after the user's confirmed reading.
4. The designated ID was present in `.codex-global-state.json` at `electron-thread-read-state-v1.legacyMigration.unreadThreadIdsByHostId.local` before reading and absent afterwards.
5. `state_5.sqlite.thread_read_receipts` had **no row** for this designated desktop conversation before or after reading. The new durable receipt map cannot be assumed to cover desktop legacy history.

The app tools are comparison evidence only: an installed third-party application cannot assume access to them. The JSON path is a **discovered private candidate**, not a stable API. Its name includes `legacyMigration`; observed correlation does not establish authoritative ownership, freshness, account isolation or long-term availability. Do not ship a universal unread mapping based on this one example.

`scripts/inspect-test-thread.py` makes reproducible metadata-only reads for a designated disposable UUID. It prints a digest, turn statuses, receipt presence and redacted membership paths. It never reads message bodies, item JSON, authentication files or task titles. The final read observation is in `artifacts/preflight/test-thread-read.json`; earlier transitions were observed in the execution tool transcript and summarized here, not reconstructed as fake raw logs.

## Local fallback investigation

Read-only schema inspection found:

- `state_5.sqlite`: thread ownership columns, archive metadata, spawn edges and read receipts.
- `thread_history_1.sqlite`: turn status and per-thread rollout ordinals, item types and projection offsets.
- Desktop JSON state: account/host-keyed unread maps plus the legacy migration structure above.

These are enough to justify a further focused adapter experiment, but not to satisfy G2/G4. Persisted `inProgress` can outlive a terminated process; metadata alone does not prove current health. Projection ordinals are not automatically a complete ordered feed of approval/input episodes. Multi-database snapshots, identity hashing, all desktop source coverage, source migration, freshness, and short-lived waits remain unresolved. No polling of task bodies or private system Focus files was introduced.

## Desktop coordination IPC: working experimental source

Further read-only inspection of the installed desktop bundle found an existing, separate coordination socket at `$CODEX_HOME/ipc/ipc.sock` (default `~/.codex/ipc/ipc.sock`). This is not the missing app-server control socket and not the authenticated app-tools interface. The observed socket belongs to the current user, with mode 0600 inside a 0700 directory. The observer does not start a router, obtain private tokens, impersonate another client, claim ownership, execute a turn, answer approvals, or write read state.

The static schema inspected belongs to desktop build **21477** (26.1016.62342). Installed source fingerprints, for reproduction rather than vendoring:

- `.vite/build/main-JI9qDiXp.js`: SHA256 `b8c5d07cc3c30fbf0abe729b05434e7d1ffa19ee6c4daa818ae8f855be66d1e1`.
- `.vite/build/src-CsH31EEu.js`: SHA256 `6a266611954c6f0c72aca09bb13c0c793959a69e8d6330778a7cdef21835a1db`.

The **historical build-21477 Swift observer** (archived in build 33) is `Archive/LegacyIPC/DesktopIPCProbe/main.swift`; the earlier Python observer is retained as a bounded discovery tool. Neither is connected to production counts. Both are restricted to an explicitly supplied disposable conversation UUID and reject unsupported desktop builds.

| Wire contract | Observed behavior / implementation |
| --- | --- |
| Framing | 4-byte little-endian JSON length; fragmented/coalesced reads supported; historical full-frame observer capped frames at 8 MiB; build 14 consumes frames incrementally with a separate 8 MiB metadata budget (see large-snapshots.md) |
| Initialize | Version 0, custom client type `status-board-observer`; uses assigned client ID |
| Owner discovery | `thread-owner-discovery` v1; the real owner is verified before accepting stream data |
| Subscribe/unsubscribe | `thread-stream-following-changed` v1, `following: true/false`; never claims ownership |
| Snapshot / delta | `thread-stream-state-changed` v11; snapshot includes revision and state, delta includes baseRevision/revision and array-path patches |
| Canonical history | Latest island entries order entities; current tail requires `newerBoundary.status == exhausted`; dictionary order is irrelevant |
| Pending requests | Request ID + method + turn ID can identify supported approval/user-input episodes; unknown methods remain unclassified |
| Read-state stream | `hasUnreadTurn` can change without advancing runtime revision; read-state broadcasts were not delivered to this observer during manual reading |
| Recovery | Initial/recovery snapshots are silent; owner changes, gaps, malformed selected patches and disconnects invalidate state; no historical alert replay |

### Real runtime sequence

The same user-authorized disposable conversation was used for all follow-ups. The Python observer captured revision 2 baseline, 3 active, 26 completed, 27 unread, and 28 final snapshot. A runtime-only subscription remained unread after the user opened the result. A fresh subscription returned **revision 28 with unread false**. Static inspection also showed the read-state setter intentionally disables follower patch broadcasting. Therefore runtime revision equality is NOT proof that unread state is unchanged.

The repaired Python observer used only the relevant read-store subtree digest as an invalidation hint, then asked the real owner for a fresh snapshot. After another real completion, it observed revision 47 unread true; following the user's confirmed reading, invalidation at monotonic 4354.536 produced revision 47 unread false at 4354.542. This is a measured 6 ms from invalidation handling to snapshot receipt, **not** a total latency or performance qualification.

The Swift observer implements that invalidation with **kqueue vnode events**, watching both the file (in-place writes) and directory (atomic replacements). It hashes only the `electron-thread-read-state-v1` subtree in memory, coalesces event handling for 250 ms, and refetches authoritative state. It never derives unread from migration membership. Its only periodic check is owner discovery every 15 seconds; there is no polling of conversation bodies. JSON/content in a received frame is temporary; only a strict state-metadata allowlist survives in `DesktopStream`. Text-only patches still advance runtime revisions.

Real Swift evidence: baseline snapshot revision 48, new run 49 onward, completion revision 62 emitted exactly one candidate completion transition, unread update 63 emitted none, snapshot 64 and same-revision invalidation refresh emitted none. No audio was played. `desktop-swift-read-refresh.jsonl` records revision 65 unread true at 01:49:05 UTC, vnode invalidation at 01:51:38 UTC, and revision 65 unread false in the same second after the user confirmed reading. Neither snapshot emitted a transition; the observer unsubscribed and exited at 01:54:05 UTC.

### Limits that remain

This solves access to a **loaded local conversation's live runtime**, including completion deltas and an observed unread-refresh gap. It does not prove a complete desktop inventory. All-page current-account ownership, unloaded/new/archived conversations, remote/cloud applicability, account changes, multi-window owner changes and wake/reconnect health still require integration evidence. Owner discovery failure is unavailable, never idle or zero.

Approval/user-input/error mappings have synthetic tests and inspected schemas; a genuine blocking user-input or approval episode and automatic-retry versus terminal-error sequence still need real fixtures. Asynchronous questions are not automatically blocking requests: the desktop derives some question state from item metadata. That mapping is deliberately not guessed. Coalesced source changes might omit a transient episode; per-thread runtime revisions are not a durable event log or a cross-thread/global sequence. Thus G4 as a whole remains unqualified, and the candidate does not activate production sounds.

Private read-store invalidation is also version-specific. Missing/unreadable schema fails the Swift observer closed. Same-revision snapshots may refresh read state silently, but cannot establish current-run read coverage for every conversation. A stable signed/installable app and an account-scoped coordinator are still required.

## Gate disposition

| Gate | Status | Remaining evidence |
| --- | --- | --- |
| G1 | IN_PROGRESS | Compare real quota; validate account switch and identity agreement |
| G2 | IN_PROGRESS | Live local runtime works; complete account-bound inventory and waiting/error/retry/cloud coverage pending |
| G3 | IN_PROGRESS | Multiple real runs and user reading observed; whole-scope current-run association, account isolation and recovery pending |
| G4 | IN_PROGRESS | Numeric per-thread runtime continuity proven on real deltas; durable wait occurrences, full bootstrap scope and reconnect coverage pending |

Evidence is in ignored `artifacts/preflight/desktop-ipc-{initial,live,after-read,invalidation}.jsonl`, `desktop-swift-{initial,live,read-refresh}.jsonl` and `desktop-probe-build.txt`. Committed tests use synthetic data only. The [official app-server documentation](https://learn.chatgpt.com/docs/app-server) remains the public transport reference; this private IPC is explicitly experimental and version-gated.
