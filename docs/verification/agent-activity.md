# Build 21 — processing agent names

Verified October 24, 2026 (America/New_York), against Codex build 21477.

The expanded details section now adds a divider below the three task counts while processing-agent rows exist. Each row shows only the final name component and `.....` while running, or ` done` after completion. A completed child remains visible until its processing root ends. Each finished root's rows are removed independently; no remaining rows means no divider or reserved vertical space. Names truncate in the middle while the status stays visible; VoiceOver exposes the complete name and status. More than five rows scroll within a bounded viewport.

## Data and lifecycle

- IPC metadata projection retains only agent path, thread ID, and lifecycle kind from `subAgentActivity`, alongside the existing status metadata. It still discards prompts, commands, and tool outputs.
- Only current turns of live, account-scoped, processing roots may produce rows. Terminal roots, waiting roots, missing coverage, and new turns cannot retain the previous run's list. Child subscriptions are removed when their root no longer needs them.
- Available child desktop streams contribute current status and nested activity. They never add to task counts, completion recovery totals, or sounds.
- Real hosted/reused subagents may have no independent desktop owner. In this case the adapter reads only turn status and agent-name metadata from local history, once per publication cycle (approximately one second). The stored child's `root_turn_id` must exactly equal the independently confirmed processing root's current turn ID. Only the child's latest turn qualifies. This fallback is restricted to inline agent rows; it never establishes top-level processing or restores old active tasks.
- A message by itself does not restart a done agent. Reused children are resolved through their current turn metadata. Unknown, interrupted, failed, or waiting states are not mislabeled as successful completion.

## Verification

- `scripts/test-core.sh`: **99 tests pass**. New coverage includes incremental metadata projection, completion patches, nested agents, per-root cleanup, next-turn isolation, waiting/interruption, child count/audio exclusion, subscription cleanup, and exact stored-root association.
- `scripts/test-window-recovery.sh`: **62 native assertions pass**, including divider/list sizing, native window growth/shrinkage, five-row viewport, folded details, and completion removal. The test executable uses its own preferences domain and does not monitor Codex.
- Light/dark and long-name fixtures inspected: [light](../../artifacts/app-validation/agents/agents-light.png), [dark](../../artifacts/app-validation/agents/agents-dark.png), [overflow](../../artifacts/app-validation/agents/agents-overflow-dark.png).
- Real application check: the existing `visibility_probe` subagent was resumed. The panel showed two running rows with one processing task, then one running row and one done row while the root remained processing. No child audio event was emitted. See [live panel](../../artifacts/app-validation/agents/live.png) and [aggregate transitions](../../artifacts/app-validation/agents/live-transitions.json). Actual root completion cleanup is covered by coordinator and native UI tests; this chat was still processing when its live evidence was collected.
- Release build **0.2.1 (21)** packaged successfully; `codesign --verify --deep --strict` passes. The rebuilt app was launched locally.

Existing partial coverage and Codex-version restrictions remain. There is no claim of complete account-wide agent coverage or live streaming command output.
