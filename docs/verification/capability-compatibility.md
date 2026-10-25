# Per-feature compatibility — build 34

Verified October 24, 2026 (America/New_York). Application: **0.2.1 build 34**.

## Behavior

The Codex build allowlist is removed. Bundle version is retained for Info/aggregate diagnostics, never used to accept or reject a connection. Compatibility is checked at the interfaces the application consumes:

- Authenticated account and user scope remain mandatory for all visible account data.
- IPC initialization must return a usable client ID; discovery must identify an owner. Explicit unsupported discovery versions or malformed success replies invalidate that conversation rather than implying it is unloaded.
- Status streams still require protocol version 11, verified owner/local host, matching conversation identity, valid revisions and continuous patches. Required runtime/request/unread/history metadata and known runtime/turn states are checked before counts or audio commit.
- Additional unrelated fields are ignored. Active runtime requires its active flags; idle/system-error variants may omit them. Missing/unknown critical states invalidate only the affected conversation and trigger resynchronization.
- Local inventory, history/read store, agent history and quota each validate their own data. Incompatible inventory hides counts immediately; transient inventory read failures retain the existing bounded 30-second grace.

## Isolation and recovery

IPC socket creation, handshake, receive and send failures now reconnect only the realtime channel with bounded backoff. The authenticated helper continues refreshing quota. A missing read-store watcher or incompatible read/history store cannot block quota or verified live conversations.

After realtime loss, old counts and queued sounds are invalidated. Previously live conversations remain blocked from older disk completions until owner discovery or a fresh snapshot establishes a safe baseline. Reconnection snapshots stay silent. Closed helpers, account changes and sustained identity verification failures still rebuild the authenticated session; identity uncertainty hides all account data.

Each snapshot carries status for live tasks, usage, history recovery and the agent list. Info presents these separately. Partial failures show **Connected · Limited** when a live source remains. Saved quota is marked **Saved** and uses the muted presentation, with an account match required. Child-agent failures do not disable top-level task status.

## Verification

- **140 Swift tests passed.** Coverage includes arbitrary new build metadata, compatible new-build sessions, additive fields, missing critical fields, unknown states, unsupported discovery/stream protocols, independent history/quota failure, immediate incompatible-inventory invalidation, missing socket/watcher at startup, socket send/receive failure, handshake recovery, silent restoration, and account-isolated saved usage.
- **98 native AppKit assertions passed.** New checks cover partial-availability labels, preserved quota with unavailable counts, per-feature Info text, diagnostic build display and accessible failure details.
- Universal arm64/x86_64 Release build, ad-hoc signature and strict signature verification passed. The only build warning was Xcode skipping AppIntents metadata extraction because this app does not use AppIntents.
- Inspected the rendered partial-availability panel and Info dialog. Generated evidence is in `.build/window-recovery/`.
- A 25-second run of the packaged application against installed Codex **21828** recorded Connected, 11 verified live conversations, one processing task, one root agent row, current weekly usage and 51 silently restored completed conversations. All four features became available; no partial/incompatible sample appeared in the final run. Total eligible local inventory was 74, with 29 legacy records excluded for unverified account attribution. This does not imply complete live coverage of unloaded conversations.
- Live shape inspection caught idle runtime legitimately omitting `activeFlags`; the validator and regression test were corrected before final packaging.

Logs: `.build/capability-tests.log`, `.build/capability-native-final.log`, `.build/capability-package.log`, and `.build/capability-validation/final-live.jsonl`. These are local generated artifacts, not application dependencies.

## Limits

New build numbers and additive fields no longer require adapter edits. A future private protocol version, required-field change, authentication change or semantic change may still need adaptation. Tests simulate changed contracts; they do not certify an unreleased Codex version. Remote/cloud coverage and formal distribution signing remain outside this change.
