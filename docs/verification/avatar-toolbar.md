# Build 15 — avatar toolbar and confirmed exit

User-requested UI update, October 24, 2026.

The expanded panel grows by 48 pt (272 pt for one quota row). A new top row contains the original `dinosaur/dinosaur-cute.png` avatar on the left and Settings, Pin, and power on the right. Clicking the avatar collapses the panel. The compact 54 pt panel uses the same avatar with a 44 pt image and retains drag/expand behavior and its waiting badge.

The Codex identity row remains below the toolbar. Its old chevron remains visible as a noninteractive image, without a click action, keyboard focus or accessibility button semantics. The Codex name/logo no longer collapses the panel.

The power button presents an attached native Cancel/Quit sheet. Cancel is the default action; Quit is marked destructive. Repeated clicks cannot stack dialogs, and an unpinned panel remains reachable while confirmation is open. Existing settings/menu-bar Quit entries use the same confirmation. Application termination requests used by lifecycle tools remain separate.

## Validation

- Universal Release build and ad-hoc signature verification pass for 0.2.1 build 15.
- Packaged avatar is byte-identical to the supplied original; no generated or edited image is substituted.
- `scripts/test-window-recovery.sh`: **33 native assertions pass**. Existing reveal/pin/focus checks are preserved; new checks cover the attached sheet, default Cancel, explicit Quit, duplicate prevention, keeping the window reachable, cancellation without exit, and confirmed termination request. The positive termination check is intercepted inside the independent probe, not the user's running app.
- Rendered and inspected the live expanded panel, light mode with two quota rows, dark settings overlay and compact waiting badge. No clipping/overlap was found. Icon buttons have descriptive accessibility labels; the unused chevron is excluded from accessibility.
- Live aggregate diagnostics confirm Connected, task counters and quota after launch. Core/streaming code is unchanged from build 14's 92 passing tests.

Evidence: `artifacts/app-validation/avatar-ui/` contains the live view, 18 light/dark design fixtures, connection diagnostics, quit confirmation rendering, build log and native-check log. This is scoped UI verification, not full VoiceOver/fullscreen/multi-display acceptance.

## Build 16 — overhanging avatar

The user requested the avatar to extend beyond the card border. The expanded avatar is now 72 pt, positioned above and slightly left of the card. The card itself remains 320 pt wide and keeps its internal layout. The native window adds transparent space (28 pt above, 8 pt left), so the visible avatar is inside the real window and stays clickable. Compact mode remains 54 × 54 pt. Settings-menu positioning and screen clamping include these gutters.

The native probe passes **37 assertions**, including real queued AppKit mouse events at a point 12 pt from the window top (above the card’s 28 pt top edge): it collapses successfully, removes the expanded gutters, and expands again when the compact avatar is clicked. Existing pin/recovery/exit checks pass. Rendered light/dark and settings views were inspected, and live connectivity was checked. Evidence is in `artifacts/app-validation/avatar-overhang/`.

## Build 17 — divider and status label colors

A divider now separates the top toolbar from the Codex identity row, using the existing vertical gap without changing the window dimensions. Processing uses the existing blue palette, Waiting for operation stays orange, and Done uses green. Only labels change color; numbers and unread dots retain their existing appearance. Disconnected labels remain gray.

Universal Release packaging and strict signature verification pass. Inspected the live dark panel, a light fixture with two quota rows, and the disconnected dark fixture. Live diagnostics confirm Connected after startup. Evidence: `artifacts/app-validation/label-colors/` contains the build log, live rendering, 18 design fixtures and aggregate diagnostics. This visual-only change does not rerun the historical core/native interaction suites.

## Build 18 — vertical spacing

The Codex identity row’s bottom spacing changes from 20 pt to 13⅓ pt (one-third smaller). The footer’s top spacing changes from 11 pt to 16.5 pt (1.5 times the original). Window dimensions are unchanged. Release packaging and strict signature verification pass. Render evidence is stored under `artifacts/app-validation/spacing/`.

Inspected the live dark panel and the light two-quota fixture: both spacings are updated with no clipping; the live panel is Connected.

## Build 19 — details disclosure

The Codex-row chevron is now an accessible Hide details / Show details button. Folding removes quota and counters from the view and shrinks the card to 140 pt (328 × 168 pt window with avatar gutters), retaining the toolbar, Codex row and Connected/Pinned footer. The top edge stays anchored. The saved details preference survives avatar collapse/expand and app restart. Opening inline Settings from the folded card expands details to fit the menu; folding dismisses Settings. Monitoring and sound delivery continue independently of this presentation state.

Validation evidence: `artifacts/app-validation/details-toggle/`.

Build 19 validation: universal Release packaging and strict signature verification pass. The native probe passes **45 assertions**, including actual chevron clicks in both directions, native size/top-edge checks, persisted preference, avatar round trip, settings expansion and dismissal, and prior window/quit behavior. The first attempt was interrupted by app activation timing; a subsequent attempt exposed a probe callback wired after its view was constructed. Binding the callback before constructing the view fixed the probe; the final full run passes. Inspected collapsed light/dark fixtures and the live expanded panel; the footer is visible and the live panel is Connected. No core data or audio code changed.

## Build 20 — smooth details animation

The details chevron now uses a 0.26-second ease-in/out transition. A shared progress value drives native window height, the clipped detail region, opacity and chevron rotation; the top edge and Connected/Pinned footer remain stable. Repeated clicks reverse from the current progress. Other window actions settle the transition before resizing, and animation timers are released on completion/termination. Reduce Motion skips the transition. Hidden details cannot receive clicks, keyboard focus or accessibility navigation.

Universal Release packaging passes. The native probe passes **53 assertions**, including intermediate heights, synchronization between native bounds and content, top-edge anchoring, jump-free reversal, completion cleanup and the immediate-layout path. An intermediate frame is captured in `artifacts/app-validation/details-animation/`, alongside the build and check logs. The system Reduce Motion preference was not changed; its immediate-layout path is covered without altering system settings.

Strict signature verification also passes. Inspected the live dark expanded view, light folded fixture and captured intermediate frame; the footer remains visible and the live panel is Connected. The app was relaunched in normal mode after verification.
