# Local temporary side chats — build 36

Verified October 24, 2026 (America/New_York), against Codex 21828.

## Cause and observed contract

The existing inventory reads account-owned, unarchived main chats from `state_5.sqlite`. A local temporary side chat is ephemeral and absent from that inventory. Its live IPC stream still exists, but the previous observer rejected its ID as out of scope.

A read-only IPC probe observed an existing side chat replayed through `thread-stream-following-changed` v1 after observer initialization. Owner discovery v1 identified its owner; stream v11 reported `sideConversation=true`, `ephemeral=true`, no `parentThreadId`, and `forkedFromId` matching the current account's main chat. The side chat was idle during this observation. The main chat was active. No prompts or conversation bodies were saved.

## Implementation

- Accept local UUID hints from follower replay and owner announcements. Keep at most 64 candidate/admitted side chats, with a 30-second candidate deadline and bounded rejection cooldown.
- Discover the owner before accepting snapshots. Promote only validated ephemeral side chats whose fork ancestry reaches a database-verified account root. Source/owner mismatch, foreign parents, subagents and ordinary unknown threads do not establish scope.
- Retain only the three additional scalar metadata fields (`sideConversation`, `ephemeral`, `forkedFromId`); navigation paths and conversation content are discarded.
- Include admitted side chats in live counts, compact status and alerts. Snapshots remain silent; only live transitions generate alerts. Side chats never enter persisted-completion recovery.
- Track window subscriptions and disconnects. A short grace tolerates remounts. Hidden running/waiting side chats remain observed; owner discovery detects discarded chats. Idle unviewed side chats release the observer subscription, allowing Codex's ephemeral cleanup.
- Drop side chat data on socket reconnect and reacquire from fresh window replay. Remove descendants when their main chat leaves the account inventory. Main-chat candidates becoming persisted inventory entries keep their verified stream.

## Verification

- `scripts/test-core.sh`: **156 tests passed**. Added cases cover replay discovery, combined and independent counts, Waiting/Done alerts, unread clearing, silent initial/reconnect snapshots, parent/account scope, subagent exclusion, owner spoofing, remount/multiple windows, close/disconnect, hidden active chats, bounded candidates, expiry, and candidate-to-main promotion. New session tests exercise the production incremental metadata decoder.
- `scripts/test-window-recovery.sh`: **98 native assertions passed**.
- Universal Release build: **x86_64 and arm64**. Ad-hoc signature verifies with `codesign --verify --deep --strict`.
- Packaged build 36 startup logged `side_chat_verified` on the user's existing side chat. Aggregate diagnostics showed Connected, all four features available, and no startup alerts. SQLite remains the bundled 3.54.1 runtime from build 35.

Logs are in `.build/side-chat-validation/` (`core.log`, `native.log`, `package.log`, `live.jsonl`). Persistent fixed-vocabulary lifecycle events are in the normal Status Board diagnostics log.

Live verification confirms discovery of the existing idle side chat. Running/waiting/completion transitions and close/reconnect edge cases were verified with deterministic tests; this validation did not send a new side-chat prompt. Scope is local temporary side chats under verified local main chats, not remote/cloud Work side chats. The private protocol is checked at runtime; future semantic changes still require review.
