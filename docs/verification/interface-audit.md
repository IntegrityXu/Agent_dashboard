# Interface audit — 0.2.1

October 23, 2026 (America/New_York).

Compared the running implementation with product specification §§2–9, the English copy table, and the original `status-board-compact.html` reference. User scope: correct the entire interface; defer Focus and audio. Later direction explicitly requires the footer to match the design rather than displaying synchronization counters.

## Corrected deviations

| Area | Previous deviation | Current implementation |
| --- | --- | --- |
| Card | Fixed 310-point height with empty quota space, 18-point padding | Width 320, radius 20, padding 16; height 224 for one quota and 267 for two |
| Typography | 25-point counts, 10-point labels, 11-point percentages | 20-point counts, 11-point labels, 14-point percentages; 12-point quota labels |
| Columns | Equal widths forced Waiting for operation onto two lines | Prototype column proportions; the full label fits on one line |
| Header | Title region did not collapse, mismatched icon sizing/direction | Title/icon collapses; consistent 30-point controls and 15-point line icons; upward collapse chevron |
| Pin | Filled icon and no layer label | Outline icon with active tint/background, plus Desktop/Pinned footer label |
| Compact view | 58-point frame, oversized logo, orange dot | 54-point frame, 28-point icon, explicit 19-point ! badge for waiting only |
| Done | No unread marker | 5-point blue dot after the number when completed-unread count is positive; none on the compact view |
| Footer | Chinese synchronized counts and local/partial label | Connected at left, Desktop or Pinned at right; disconnected variants exactly follow the copy table |
| Quota | Untinted percentage; system-neon progress colors | Matching percentage/progress tones and the reference's muted adaptive green/orange/red palette |
| Appearance | Opaque regular material and lower-contrast secondary text | Neutral ultra-thin native material; reference-based muted text and adaptive colors; per-control hover/press states |
| Time help | “Resets”, and a heartbeat date presented as Last updated | “Reset at” with local date/time; Last updated only uses a complete successful sync timestamp, or — |
| Offline | Lost last quota values; colored task/usage affordances | Same-account saved quota retained, frozen and gray; task counts —; waiting/unread markers cleared |
| Identity | No restart quota cache | Metadata-only quota cache; hidden until account identity is verified, never shown under another/unknown account |
| Initial state | First launch expanded and pinned | First launch compact and unpinned; existing saved preferences preserved |
| Recovery | Menu-bar show did not save expanded form | Show Status Board persists expansion; monitor movement/resize stays anchored; remembered display is used when present |
| Settings | Already corrected in the prior turn | Exact three entries retained; native keyboard event handling includes arrows, Tab, Home/End, Return/Space and Escape |

The no-leading-icons/no-inequality-sign instruction remains in effect. Done's small **trailing unread dot** is the required status marker from the design, not a restored leading icon.

## Coverage disclosure

The adapter still confirms only a subset of the current account's local top-level conversations. This audit does **not** claim complete local/remote/cloud account coverage. Following the user's footer correction, coverage is disclosed in the connection tooltip and task-button help, not permanent footer text. Connected describes a functioning live source; counts represent the confirmed subset. Full-account successful synchronization has not occurred, so Last updated is — rather than a fabricated heartbeat timestamp. Quota snapshots still retain their independently verified fetch time internally.

## Evidence

- **37 Swift Testing tests passed**. Five additional tests cover saved-quota freeze past reset, restart/unknown/different-account isolation, partial-scope timestamp honesty, three-second failure grace/ten-second silent-worker expiry, and immediate clearing across identity changes.
- Debug and universal Release builds succeeded. The real source remained connected during the integrated run, with 5/67 confirmed local conversations and current account quota; this is observed data, not a fixture.
- Rendered **18 offscreen fixtures** across light/dark appearances: mixed, unread-only, waiting-only, saved-usage disconnect, empty first launch, settings, compact waiting, compact completed-only and compact disconnected. Inspected layout, full labels, marker rules, contrast, and gray offline tones. These fixtures never replace live state or change preferences/system settings.
- Actual live captures: `artifacts/app-validation/final-design.png` (before final footer-only correction), `interface-final.png` (delivered footer); fixture renders under `artifacts/app-validation/design-cases/`; test output `design-tests.txt`.
- Real app restart/quit performed without stopping Codex or changing login items. Release signature verified by the packaging script.

Keyboard/mouse handlers are implemented; complete manual VoiceOver, display-removal, login-cycle and desktop-background blur inspection are not claimed as passed by offscreen rendering. Earlier user-confirmed fullscreen/Spaces/click-to-front behavior is retained. Focus authorization, Focus state integration and audio playback remain deferred.
