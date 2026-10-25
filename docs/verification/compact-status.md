# Build 22 — latest compact status

Verified October 24, 2026 (America/New_York), against Codex build 21477.

The collapsed avatar now shows exactly one badge: an orange `!` for Waiting for operation or a green `✓` for Done. A newer event replaces the previous badge. Resolving/reading the newest task selects the most recent still-outstanding task; clearing both states removes the badge. Stale/disconnected data uses the existing presentation expiry rules. Tooltip and accessibility text describe the selected state and its task count.

Recency is tracked per top-level task and turn from accepted live IPC transitions, independently of audio and mute. Replacing one waiting task with another can change the badge even when counts stay the same. Late unread flags, ordinary refreshes, replayed patches, and history snapshots do not create new priority. Child agents do not affect this badge. Heartbeat completions can update it even while their audio remains suppressed.

On startup or a new connection, restored states have no verified relative event order. Waiting is the deterministic baseline if both are present; the next observed live event establishes priority. Task recency is not persisted across account/session changes.

Validation:

- **106 Swift tests pass**, including bidirectional replacement, unchanged totals, read/resolve fallback, delayed unread changes, replay, new turns, request/flag ordering, heartbeat/error states, and the real session coordinator's published badge.
- **70 native assertions pass**, including both states with unchanged counts, done-only, empty, expired, and accessible descriptions.
- Inspected compact light/dark fixtures: [Waiting/light](../../artifacts/app-validation/compact-status/compact-latest-waiting-light.png), [Done/light](../../artifacts/app-validation/compact-status/compact-latest-done-light.png), [Waiting/dark](../../artifacts/app-validation/compact-status/compact-latest-waiting-dark.png), [Done/dark](../../artifacts/app-validation/compact-status/compact-latest-done-dark.png).
- Release **0.2.1 (22)** built, packaged, signature-verified, and relaunched locally. No real user-facing wait requests or unread tasks were manufactured for this verification.
