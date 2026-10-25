# Native feasibility

> Historical native/Focus probe report. The integrated build 7 panel, settings/login API and quit-isolation smoke now exist; see [current status](results.md) and [release qualification](release.md). The observations below retain their original probe scope. Focus/audio remain deferred, and full native/login-cycle acceptance remains pending.

Observed October 23, 2026 (America/New_York), Intel macOS 15.8.1; Xcode 26.3 / Swift 6.2.4. See [environment.md](environment.md) and `source-manifest.json`. No login registration or sounds were enabled. The user performed the stated Focus/desktop actions; the agent did not alter system Focus configuration.

## Window experiment and fixes

The independent `local.statusboard.nativeprobe` application supports `--inspect`, `--smoke`, and `--interactive`. Launch the interactive bundle with `bash scripts/run-native-probe.sh`, which uses Launch Services. The menu-bar `SB 测试` entry can restore a hidden panel or quit the probe. This recovery menu is probe instrumentation, not a change to the product's three-item settings menu.

| Check | Result | Evidence |
| --- | --- | --- |
| Current Swift/AppKit compilation | PASS | `probe-build.txt` |
| 54×54 / 320×200 form, Pin independent of form | PASS, programmatic | `native-smoke.txt` |
| Pinned above native fullscreen | PASS, user confirmed | User reported fullscreen and both desktops visible after collection-behavior fix |
| Pinned across two desktop Spaces | PASS, user confirmed | Same confirmation; `native-fullscreen-spaces.txt` records actual space changes |
| Unpinned below ordinary windows | Observed | User confirmed panel remained underneath windows |
| User click temporarily raises unpinned panel; outside click lowers it while preserving form/Pin | PASS, user confirmed | Latest response “符合预期”; `native-launchservices.txt` records levels/key state |
| Initial automatic launch/source updates do not intentionally activate | Implemented, not full acceptance | `orderFrontRegardless`; only a user click calls `makeKeyAndOrderFront` |
| Multiple screens/removal/scale changes | NOT_RUN | Only one screen connected |
| Persistent position, drag-vs-click, all fullscreen/Spaces variants | Incomplete | Not qualified by this limited window session |

Changes from the original candidate:

1. The original `desktopWindow + 1` panel was hard to recover and below the desktop icon layer. The test now uses normal-window level minus one for resting unpinned state, level zero only during a user interaction, and floating level for persistent Pin.
2. Collection behavior adds `canJoinAllApplications` to `canJoinAllSpaces`, `fullScreenAuxiliary`, and `stationary`. The current SDK describes the former as suitable for floating windows/overlays joining application sets and fullscreen Spaces.
3. Explicit “置顶 / 取消置顶” text replaces an ambiguous pin-only control in the probe. The panel started pinned; the first reported disappearance after clicking Pin was an unpin operation, not a process crash.
4. A nonactivating panel may become key only on deliberate user interaction. Losing key status lowers an unpinned panel. Collapse/expand and background updates preserve Pin and do not independently raise the window.

The user requested click-to-front behavior during this session. It is now recorded in product §2. This is an explicit interaction clarification, not automatic foregrounding on data changes. G5 remains IN_PROGRESS because display removal and the wider native matrix are untested. Tests passed on the probe, not an integrated product release.

## Focus experiments

### Minimal public status probe

Directly invoking the bundle executable caused a TCC abort on the first authorization click. The crash explicitly reported a missing `NSFocusStatusUsageDescription`, although the key existed in our Info.plist. Launching the same app via Launch Services resolved the attribution/launch-context problem: the system showed a permission prompt and authorization became **3 (authorized)**. Treat the explanation as an inference from those two observations, not an assertion about an inspected TCC implementation.

The user then toggled Do Not Disturb for the requested intervals. The status stayed **false**. The user first confirmed status sharing was disabled, then enabled sharing and repeated the test; the result still stayed **false**. Therefore neither permission alone nor changing sharing alone qualified this minimal probe. Ad-hoc binary rebuilds also reset its authorization in this experiment. An unauthorized false is never evidence that Focus is off.

Evidence: `native-interactive.txt` (pre-fix crash), `native-before-layer-fix.txt` (successful Launch Services authorization), `native-fullscreen-spaces.txt`, and `native-launchservices.txt` (final interactive build). The user's on/off actions are confirmation evidence; no private Focus database was read to infer them.

### Capability-complete request path prepared; signing blocks execution

Apple's [communication/Focus sample](https://developer.apple.com/documentation/UserNotifications/handling-communication-notifications-and-focus-status-updates) documents Focus authorization, notification authorization, and the Communication Notifications entitlement as prerequisites. Its Focus status is **app-relative**: an allowed-through app can see false while Focus is enabled. It also uses an Intents extension for background change delivery. The minimal probe lacked notification authorization and this entitlement, so its false result cannot prove a platform-wide API failure.

Added `Probes/FocusProbe/` with a separate normal window and button that requests sound-only notification permission plus Focus permission, then samples public status. It never schedules a notification or plays a sound. It declares `com.apple.developer.usernotifications.communication` and has its own bundle ID. Background Intents-extension delivery is not implemented by this foreground feasibility probe.

The ad-hoc build compiled and passed `codesign --verify`, but **macOS rejected its launch**. The diagnostic report says `SIGKILL (Code Signature Invalid)` and `Taskgated Invalid Signature`. This is an operating-system signing failure, not an agent approval rejection. The local `security find-identity -v -p codesigning` check reported **0 valid identities**. No signing identities, profiles, Apple accounts, or security settings were created or changed. The filtered crash summary is retained as `focus-launch-failure.json`; the temporary broad-format system log was discarded.

A real Xcode target and shared scheme **StatusBoardFocusProbe** are prepared in `StatusBoard.xcodeproj`, with automatic signing and the entitlement file. Its unsigned compile check succeeds; **unsigned compilation is not permission/capability validation**. To continue: select this target's Signing & Capabilities, use the user's legitimate Team and a bundle identifier/profile supporting Communication Notifications, then run through Xcode/Launch Services. Do not remove the required entitlement or disable signature validation to obtain a misleading pass. `scripts/build-focus-probe.sh` only reproduces the ad-hoc feasibility build and its current limitation.

G6 is **BLOCKED for the current route**. Valid signing/capability execution is the next prerequisite. Even after that, sharing-off, denied/revoked, allowed-through-app, background freshness and queue cancellation cases remain. App-relative status alone cannot certify the product's strict “any Focus means silence” rule. Audio remains unimplemented/disabled; no fallback treats unknown or unauthorized false as permission to sound. The user's final reported system setting is sharing **enabled**; the agent did not revert it.

## Lifecycle

At this historical probe checkpoint, G7 was NOT_RUN and login service status was only read (notFound). All interactive probes started in that session were closed; the disposable conversation was left available and read. Later preview work integrated the application, login registration and quit-isolation smoke. Current G7 is IN_PROGRESS; stable installation and actual login cycles still need qualification. See [release status](release.md).
