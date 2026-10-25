# Usable preview — integration record

Current version **0.2.1 build 7**: use the [current progress index](results.md) for implementation and remaining work. The [interface audit](interface-audit.md) and initial 0.2.0 observations below are checkpoint evidence. Latest recorded validation is 48 passing tests; the 32-test count below belongs to the initial integration.

Date: October 23, 2026 (America/New_York).

## Authorized milestone

The user explicitly requested a usable version with real-time task counts first, deferring Focus and sound. This supersedes the earlier requirement to finish all feasibility gates before connecting the panel. It does not mark the complete original specification or whole-account coverage as accepted.

Deliverable: `dist/Status Board.app`, a locally ad-hoc signed Release application. Focus, audio and notarized distribution are not part of this milestone. The follow-up settings correction adds user-initiated login registration; an actual login-cycle check remains pending.

## Build 4–7 updates

- [Build 4](done-reconciliation.md): periodically reconcile completed/unread live contributors against authoritative read snapshots.
- [Build 5](reconnect.md): healthy IPC plus quota restores Connected before conversation owners load; full manual quit/reopen acceptance remains pending.
- [Build 6](unloaded-unread.md): silently recover unloaded completed/unread local conversations from scoped read state and completion metadata.
- [Build 7](read-clears-done.md): query eligible inventory completion metadata independently of unread IDs, preserving numeric counts when the last unread becomes read. Live observations retain precedence; history never fabricates processing/waiting.

These updates supersede the initial live-owner-only Done behavior below. Complete runtime coverage and complete-sync timestamps remain unqualified.

## Initial integration implementation

`StatusBoardDesktop` owns a background worker and a read-only CLI helper. Account identity is refreshed every 15 seconds; quota every 60 seconds. SQLite read-only metadata inventory refreshes every 5 seconds, excluding archived records, child agents and nonmatching accounts. At most 512 current-account IDs are subscribed; excess records remain in the total and therefore keep partial coverage visible.

Desktop coordination IPC uses an independent observer identity, owner discovery, version-11 snapshots/patches, and revision continuity validation. Metadata projection drops titles, prompts, paths and tool contents. File/directory vnode events detect the read-store changing and request authoritative snapshots. The store never supplies count values. Owner loss, gaps, unsupported shapes and socket disconnects remove unverified observations. Reconnection uses bounded backoff. Account changes discard the entire session and quota. No counts are restored from disk.

The worker emits aggregate state at most once per second. The UI shows unavailable data if the worker has not published in ten seconds. Account/quota RPC calls have a five-second timeout. In 0.2.1, persistent source/usage failures enter a unified disconnected state with verified same-account saved usage. Account verification failure hides the cache.

The panel uses the previously user-verified window behaviors: all Spaces, fullscreen auxiliary, floating when pinned, below normal windows when unpinned, temporarily normal-level on explicit click. The app includes collapse/expand, header/icon dragging, screen clamping, position/pin/form persistence, a menu-bar recovery entry, single-instance activation and graceful helper shutdown. The initial preview launched expanded and pinned; 0.2.1 restores the specified first-launch compact/unpinned defaults while preserving existing preferences.

User revision: task counts are **plain numbers**, without leading symbols or ≥. In 0.2.1, coverage is disclosed in status/task tooltips as requested; permanent footer content follows the product design. Do not interpret a partial count of zero as proof that the entire account has no tasks.

## Observed checks

Environment: Xcode 26.3, Swift 6.2.4, SDK 26.2, Intel macOS 15.8.1; Codex build 21477.

- **32 Swift Testing tests passed**, including four new tests for blocking-state precedence, missing read evidence, unknown requests, error/stopped classification, and account/archive/child inventory filtering. Existing stream tests cover gaps, same-revision read refresh, malformed patches and source projection.
- Integrated Debug app built and ran through Launch Services. Actual view was rendered from its own content view, without screen capture permissions.
- Current-account inventory contained **67** top-level unarchived local conversations; **4** had usable live observations. **29** older top-level records had no creator account and were excluded. These are observations from this run, not hardcoded constants.
- Live quota supplied a weekly window with **78% remaining**. No short cycle was invented when the source omitted it.
- Authorized disposable conversation: before test **processing 1 / Done 0**; during its 20-second wait **processing 2 / Done 0**; completed at 02:13:48 UTC, panel sample at **02:13:49 UTC** showed **processing 1 / Done 1**.
- User manually read “面板实时计数验证完成”. The integrated panel reported **Done 0** by **02:14:01 UTC**, without another turn or programmatic read mutation.
- Release package built for **x86_64 + arm64** and passed `codesign --verify --deep --strict`. The final plain-number layout was inspected from the actual running view.
- Exit verification initially exposed a nested AppKit termination-loop/main-queue deadlock. Cleanup completion now replies through the main run loop. In the repaired 12-second Release smoke run, both the app PID and its recorded helper PID disappeared; the pre-existing Codex helper remained untouched.
- Evidence: `artifacts/app-validation/live.jsonl`, `core-tests.txt` and own-view PNG. Diagnostics are opt-in and aggregate-only; normal launch writes no diagnostic log.

## Limits and remaining qualification

Live processing/waiting coverage still depends on verified live observations. Builds 6–7 also recover completed/read and completed/unread local contributions without a live owner; they do not establish complete runtime coverage. Cloud/remote task coverage is not implemented. Real approval/error episodes, account-switch interaction, prolonged stability, display removal and all original acceptance cases remain unqualified. The source is private and version-pinned; future Codex updates may require an adapter update.

The user's previously confirmed native fullscreen/Spaces/click behavior is reused, but that is not a claim to have rerun every native manual case on this package. No additional Focus permission or system-setting change is required to use this preview.

## Settings follow-up

The user requested the specified menu content and a visual style consistent with the dashboard. The gear now opens an in-card overlay with matching material, a 12-point corner radius, subtle border/shadow, and 32-point rows. It contains exactly Mute Sounds, Launch at Login, Quit in that order. It does not shift card layout and remains within the already screen-clamped panel. Hover/keyboard selection highlights a row; checked settings use checkmarks.

Mute Sounds persists the preference without enabling the deferred audio service. Launch at Login reads SMAppService.mainApp.status; registration/unregistration occurs only on an explicit user action. Pending approval routes to macOS Login Items settings; errors remain visible instead of displaying a fabricated enabled state. No system login setting was changed during validation.

Release compilation and strict bundle-signature verification passed. The actual running menu was rendered and inspected (`artifacts/app-validation/settings.png`). Escape, outside-click, keyboard navigation and focus restoration are implemented; full manual keyboard/VoiceOver and actual login-cycle validation remain pending. Refresh/Open Codex are retained in the distinct menu-bar recovery menu, not the gear dropdown.
