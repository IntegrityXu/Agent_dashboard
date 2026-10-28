# Implementation and verification results

Reviewed October 27, 2026 (America/New_York), against the current source and existing verification records. Current application: **0.2.3 build 40**, using per-feature contract checks instead of a build allowlist. The original private contracts were inspected on Codex builds 21477 and 21828; future semantic compatibility is not guaranteed.

Build 40 title/sound preview: chat display names replace repeated root labels, child-agent rows are indented, and the completion sound is a 650 ms wooden double tap. **165 Swift tests, 185 native assertions, universal Release packaging, archive/resource and extracted-signature checks passed.** See [build 40 release verification](title-sound-build-40.md).

Build 39 red-fox preview: new awake/sleeping avatar, application and menu bar artwork, a 30-minute conversation-idle timer, bundled legal notices, and repeatable ZIP/checksum packaging. **163 Swift tests, 185 native assertions, universal Release build, archive/resource checks and extracted-app signature verification pass.** See [build 39 release verification](fox-preview-build-39.md).

Build 38 public preview: **156 Swift tests, 185 native assertions, universal Release/ZIP/signature checks passed.** See [build 38 packaging](passive-focus-drag.md#github-preview-packaging--october-26-2026).

Build 37 interaction repairs: expanded and compact avatar dragging share an event-driven gesture, subsequent strip drags require no recovery click, both avatar help bubbles are removed, and all count cells use verified native hand cursors. **156 Swift tests, 119 native assertions and universal Release/signature checks pass.** See [avatar and cursor verification](avatar-drag-cursor.md).

Build 36 side chat detection: owner-verified live discovery of local ephemeral side chats, account-scoped parent validation, independent counts/alerts, hidden-running retention, and close/reconnect cleanup. **156 Swift tests, 98 native assertions, universal Release/signature checks, and live side-chat discovery pass.** See [side chat verification](side-chats.md).

Build 35 idle database recovery: pinned, namespaced standard SQLite fixes read-only reopening after the writer removes WAL sidecars. **146 Swift tests, 98 native AppKit assertions, universal Release/signature checks and live startup pass.** See [idle database investigation and verification](sqlite-idle-recovery.md).

Build 34 compatibility: independent IPC reconnects, schema and state validation, additive-field tolerance, independent history/usage/agent degradation, and feature-specific Info messages. **140 Swift tests, 98 native UI assertions, universal Release packaging and live Codex 21828 validation pass.** See [compatibility verification](capability-compatibility.md).

Build 33 audit fixes: bounded IPC draining/partial-frame grace, transactional quota validation, verified saved-usage fallback and explicit stream-alert lifecycle. Duplicate refresh entry points removed, app/session responsibilities split, obsolete probes and lens experiments archived. **130 Swift tests, 93 native UI assertions and the universal Release build pass.** Packaged build 33 is running; live Connected state, quota and counts were verified. See [build 33 verification](review-fixes-build-33.md).

Build 32 reliability update: independent data reads retry without tearing down IPC; only the affected stream is invalidated on a stream protocol mismatch. Persistent rotating diagnostics record source, safe error code and recovery. **120 Swift tests and the universal Release build pass**; the updated packaged app was launched and verified Connected with live counts and automatic build-32 log entries. See [fault isolation verification](fault-isolation.md).

Build 31 discovery update: new and renewed activity plus verified-protocol owner announcements receive priority; two discovery slots remain available while historical discovery waits. **111 Swift tests pass**, including multiple-conversation counts and canonical Waiting/Done delivery through the audio queue. See [multiple-conversation and audio validation](multi-conversation.md).

Build 30 compatibility update: Codex 21828 is supported, version/protocol failures have explicit presentation, bundle metadata is rechecked after in-place updates, and initial discovery preserves inventory recency order. **107 Swift tests, 93 native assertions and the universal Release build pass.** See [current compatibility and live validation](codex-21828.md).

Build 29 interaction update: count tooltips removed, clickable counts use pointing-hand cursors, both menus expose an Info dialog, and other panel hints use a 0.35-second delay. **89 native assertions and the universal Release build pass**; the packaged app was launched from `dist`. See [Info and hover verification](info-hover.md).

Current source review fixes (October 24, 2026): patch-field-order handling, authenticated-user cache isolation, and expiry of queued sounds are corrected. Unused prototype contracts are removed, app views/previews are separated from window control, and shared waiting-state logic is centralized. **99 Swift tests, 70 native assertions, the desktop probe build, and universal Release build pass.** See [review fixes and cleanup](review-cleanup.md). Packaged as build 28 and verified against the live local Codex source; see the release evidence in the linked report.

Build 27 lowers the dark material-only opacity from 0.88 to 0.76 at the user’s request. The native frosted material remains; foreground text, icons, borders and all interactions are unchanged. Reduce Transparency still uses full opacity.

Build 26 slightly increases transparency of the dark frosted backgrounds in both forms by applying 0.88 opacity to the material alone. Foreground text, controls, borders, geometry and status logic are unchanged. Reduce Transparency keeps full material opacity. Universal Release/signature checks and all 70 native assertions passed; [test log](../../artifacts/app-validation/frost-opacity/native-tests.log).

Build 25 restores SwiftUI `.ultraThinMaterial` backgrounds on both forms. ScreenCaptureKit/Metal code, the preview tour and capture permission description are removed from the application target; the experimental source remains only in historical probes. Layout and task behavior are unchanged. Universal Release and signature verification passed; 70 native assertions passed again. The packaged executable no longer links ScreenCaptureKit or MetalKit. [Restoration test log](../../artifacts/app-validation/frost-restored/native-tests.log).

Historical experiment: Build 24 adds an explicitly enabled ScreenCaptureKit/Metal desktop-lens experiment. Live capture and rendering were observed for both expanded and compact forms, and six GPU assertions pass on the host GPU. See [desktop lens evidence and limitations](desktop-lens.md).

Build 23 applies a shared liquid-glass background to the expanded panel and compact avatar. **70 native assertions pass**, universal Release builds and signature verification succeeds. macOS 15 uses a public AppKit compatibility treatment; the macOS 26 native glass path is compiled but not runtime-tested on this host. See [glass material evidence](liquid-glass.md).

Build 22 adds a single compact Waiting/Done badge selected by live event order. **106 Swift tests and 70 native assertions pass**; see [compact status evidence](compact-status.md).

Build 21 adds the processing-agent list and temporary divider below the task counts. **99 Swift tests and 62 native assertions pass**; a real reused subagent was observed running and then done without changing the top-level processing count or producing an audio event. See [agent activity evidence](agent-activity.md).

This is the current progress index. Build 14 has **92 passing Swift tests**, covering streaming metadata selection, live-event delivery and the serial audio service. See [audio implementation and validation](audio.md); build 9's session-timing evidence remains in its [dated report](session-timing.md). Full real-source/manual acceptance is not implied by deterministic tests.

The user subsequently requested audio implementation. Build 10 enables completion/wait/error sounds and manual mute; **Focus integration remains deferred**. Direct audio does not automatically honor macOS Focus. The complete original specification remains unqualified.

Build 12 fixes covered-panel recovery and adds direct menu-bar Pin/Unpin, with **26 passing native AppKit assertions** including WindowServer ordering and a real application switch. See [window recovery](window-recovery.md). Fullscreen/Spaces and physical menu-click acceptance remain separate.

Build 14 replaces full-frame buffering/decoding with incremental metadata projection after a real 8,697,586-byte snapshot repeatedly disconnected the observer. Content is skipped during receipt; state, IDs, unread flags and revision continuity are retained. The temporary buffer-limit increase was superseded at the user’s request. Large snapshots/patches, arbitrary JSON property order, async answers and canonical history have regression coverage. See [large snapshots](large-snapshots.md).

Build 15 adds a taller avatar toolbar with Settings, Pin and power/confirmed Quit. The avatar collapses the panel and is reused in compact mode; the old chevron is reserved without an action. See [avatar toolbar](avatar-toolbar.md): 33 native assertions pass, and visual fixtures were inspected.

Build 16 enlarges the avatar to 72 pt and moves it across the card’s upper-left border. A transparent window gutter preserves clicking above the card; 37 native assertions pass, including collapse/expand via actual AppKit mouse events. See [avatar UI](avatar-toolbar.md#build-16--overhanging-avatar).

## Implemented in the current preview

| Area | Current behavior | Evidence and limits |
| --- | --- | --- |
| Native panel | Expand/collapse, dragging, pinning, position/form persistence, temporary menu-bar reveal, direct menu-bar Pin/Unpin and single-instance activation | [Build 12](window-recovery.md), [interface audit](interface-audit.md); full native matrix pending |
| Task and quota data | Read-only account/quota helper, local inventory and live desktop IPC; processing/waiting/Done for the verified subset | [Preview](usable-preview.md); counts are not whole-account totals |
| Connection and saved quota | Reconnection, unified disconnected presentation, same-account frozen quota; unknown data remains unavailable | [Interface audit](interface-audit.md), [build 5](reconnect.md) |
| Done reconciliation | Authoritative read refresh removes read completions without writing Codex state | [Build 4](done-reconciliation.md) |
| Restart/reconnect Done recovery | Restore unloaded completed/unread local conversations silently | [Build 6](unloaded-unread.md); does not recover live processing/waiting from history |
| Reading the last unread | Preserve verified completed/read coverage so Done becomes 0 while live owners are loading | [Build 7](read-clears-done.md); baseline is refreshed and superseded by live observations |
| Review fixes | Runtime survives missing history; full eligible inventory; retry reset after a healthy session; expired live data stays hidden; heartbeat counts agree across sources | [Build 8](review-fixes.md); UI unchanged and baselines remain silent |
| Session timing | Discovery deadline includes router lookup; bounded late replies; read changes during a pending snapshot trigger one follow-up | [Build 9](session-timing.md); deterministic session regressions, unchanged UI and silent baselines |
| Settings | Immediate mute/cancellation and saved preference, system-backed Launch at Login registration/unregistration, Info, Quit | [Preview](usable-preview.md); actual login cycle pending |
| Async questions | Unanswered async questions count as waiting and trigger a live waiting-entry sound; accepted replies clear the state | [Build 11](async-questions.md); user-confirmed waiting count and audible sound, with reply clearing verified in live logs |
| Audio | Three bundled short sounds, serial completion-driven playback, deduplication, manual mute and cancellation on source/lifecycle changes; silent startup/recovery | [Build 10](audio.md); Focus and full real-event listening matrix remain pending |
| Packaging and exit | Runnable universal Release app, local ad-hoc signing; observed shutdown of only the app and its own helper | [Release](release.md); formal distribution and full lifecycle acceptance pending |

## Not implemented or incomplete

| Remaining work | Current boundary |
| --- | --- |
| Focus integration — deferred by user | No reliable production Focus provider. Earlier capability/signing and app-relative status limitations remain documented in [native feasibility](native-feasibility.md). |
| Complete task coverage | Live runtime covers only part of current-account local top-level inventory. Persisted completion/read recovery extends Done coverage, not processing/waiting coverage. Remote/cloud coverage is not implemented; legacy records without verified account identity are excluded. |
| Codex version compatibility | Build numbers are diagnostic only. Runtime contract checks accept compatible updates; changed private protocols/semantics may still need adapter changes. |
| Formal distribution | No notarized distribution or qualified stable installation workflow. The locally ad-hoc-signed preview already runs. |

## Implemented but awaiting broader verification

- Launch at Login: actual enabled/disabled logout/login cycles, system approval/error outcomes and final stable-path behavior.
- Audio: confirm audible distinction/comfortable volume and real approval/error/retry behavior on the final app; Focus suppression is still absent.
- Real task transitions: approval/input waits, stopped errors, retries, repeated/short waiting episodes, complete event continuity and source coverage.
- Identity and recovery: real account switching, broader sleep/wake/fault-injection coverage, and the full Codex quit/reopen-without-message scenario. Build 5 has deterministic and live-startup evidence, not a completed manual restart matrix.
- Native interaction/accessibility: display removal, multiple screens/scales, the complete fullscreen/Spaces matrix, VoiceOver and full manual keyboard/mouse checks. Earlier user-confirmed fullscreen/two-Spaces/click-to-front checks remain valid within their stated scope.
- Performance/stability: release latency measurements, ten-minute idle CPU/memory baseline and two-hour ordinary-use session. See [performance](performance.md).
- Full acceptance: remaining original A01–A54 procedures and final-bundle lifecycle checks. Existing tests, rendered fixtures and smoke runs are evidence for their stated scenarios, not blanket acceptance.

## Step status against the full specification

`IN_PROGRESS` means implementation or evidence exists but the original step's full pass criteria are not met. Deferred features are not silently waived.

| Step | Status | Current implementation / remaining work |
| --- | --- | --- |
| S00 | PASS | Recorded environment and compiler preflight |
| S01 | IN_PROGRESS | Selected version-pinned source integrated; complete scope and event contract pending |
| S02 | IN_PROGRESS | Native subset verified; full matrix and Focus capability unresolved |
| S03 | IN_PROGRESS | Xcode application and shared packages built; full-spec integration decisions remain open |
| S04 | IN_PROGRESS | Core/adapter suite: latest recorded 92 passing tests; complete V09 qualification pending |
| S05 | IN_PROGRESS | Live adapter, recovery and unread reconciliation implemented; full-source qualification pending |
| S06 | IN_PROGRESS | Native widget and interface audit implemented; full manual/accessibility acceptance pending |
| S07 | IN_PROGRESS | Settings, login API and serial audio implemented; Focus deferred; real login cycle pending |
| S08 | IN_PROGRESS | Integrated preview and build 4–9 recovery fixes verified in stated scenarios; broad fault matrix pending |
| S09 | IN_PROGRESS | Interface fixtures and regression checks recorded; full acceptance/performance qualification pending |
| S10 | IN_PROGRESS | Personal preview packaged; stable installation, distribution signing and final lifecycle qualification pending |

## Verification and gate disposition

| Procedure | Status | Evidence / next qualification |
| --- | --- | --- |
| V01 — Identity/quota | IN_PROGRESS | Live reads and deterministic cache/isolation checks; full comparisons and real switching pending |
| V02 — Task states/scope | IN_PROGRESS | Real processing/completion observations; full scope and wait/error/retry scenarios pending |
| V03 — Done/read semantics | IN_PROGRESS | Builds 4, 6 and 7 cover real read clearing and unloaded recovery; full procedure pending |
| V04 — Event identity/bootstrap | IN_PROGRESS | Stream/core regression checks and silent recovery; continuous per-thread live-patch boundary tested through audio delivery; durable whole-source coverage pending |
| V05 — Health/synchronization | IN_PROGRESS | Health coordinator, disconnect/reconnect and saved-quota behavior implemented; full failure matrix pending |
| V06 — Native windows | IN_PROGRESS | Native subset and integrated panel evidence; full screen/Spaces matrix pending |
| V07 — Focus | BLOCKED | Historical capability/signing route unresolved; production integration deferred by user |
| V08 — Login/lifecycle | IN_PROGRESS | Login API, preference handling and quit-isolation smoke implemented; actual login cycles pending |
| V09 — Deterministic tests | IN_PROGRESS | Latest recorded 92 tests pass; full original fixture/fault suite not certified |
| V10 — UI/accessibility | IN_PROGRESS | Interface audit and 18 rendered fixtures; full manual/accessibility checks pending |
| V11 — Audio | IN_PROGRESS | Playback/queue, mute, suppression and driver tests implemented; see build 10 evidence; full real wait/error/Focus listening matrix pending |
| V12 — Fault recovery | IN_PROGRESS | Reconnect/read recovery and deterministic cases recorded; broader fault matrix pending |
| V13 — Performance | NOT_RUN | No formal latency/resource/stability measurements |
| V14 — Release | IN_PROGRESS | Release package/signature checks pass; complete final-bundle qualification pending |

G1–G5 remain `IN_PROGRESS`: the preview has evidence for identity, local runtime, unread recovery, stream ordering and native behavior, but none of these claims complete original scope. G6 remains `BLOCKED` on the documented Focus route and is deferred for the preview. G7 is `IN_PROGRESS`: packaging and quit-isolation evidence exist, but stable installation and real login-cycle qualification remain open.

Original A01–A54 requirements and their procedure mapping remain in the [implementation plan](../status-board-implementation-plan-v0.1.md#7-product-acceptance-traceability). This review does not mark them all passed or treat missing manual evidence as missing implementation. The old individual-case tables are retained in the [historical checkpoint](results-pre-preview.md), not used as current delivery status.

## Evidence index and maintenance rule

- [Environment](environment.md), [historical source investigation](codex-integration.md), [native/Focus probes](native-feasibility.md).
- [Initial integrated preview](usable-preview.md), [interface audit](interface-audit.md).
- [Build 4: Done reconciliation](done-reconciliation.md), [build 5: reconnect indicator](reconnect.md).
- [Build 6: unloaded unread recovery](unloaded-unread.md), [build 7: last unread clears to zero](read-clears-done.md).
- [Build 8: logic fixes and structure](review-fixes.md), [build 9: session timing](session-timing.md).
- [Build 10: audio delivery and cancellation](audio.md), [build 11: async questions](async-questions.md).
- [Build 12: covered-panel recovery and menu-bar Pin/Unpin](window-recovery.md).
- [Build 14: streaming metadata selection](large-snapshots.md).
- [Build 15: avatar toolbar and confirmed exit](avatar-toolbar.md).
- [Performance qualification](performance.md), [release qualification](release.md).
- [Archived pre-preview checkpoint](results-pre-preview.md). Its scaffold-only restrictions and test counts are historical.

Use this index for current remaining work. Keep per-build reports as dated evidence, update this index when behavior or qualification changes, and record the actual build/test scope before marking an acceptance case passed. Build 10 implements audio at the user's request while preserving the saved mute preference. Login and Focus settings are unchanged; no Codex conversation is modified for audio tests.

Build 17 adds the Codex-row divider and blue/green processing/Done labels. Release packaging, signature verification, light/dark rendering and live connectivity were checked; see [UI evidence](avatar-toolbar.md#build-17--divider-and-status-label-colors).

Build 19 enables the details chevron while retaining Connected/Pinned. Release/signature checks, 45 native interaction assertions and light/dark visual checks pass; see [details disclosure](avatar-toolbar.md#build-19--details-disclosure).

Build 20 adds smooth details disclosure with synchronized native height/content and rapid reversal. The native probe passes 53 assertions; see [animation verification](avatar-toolbar.md#build-20--smooth-details-animation).
