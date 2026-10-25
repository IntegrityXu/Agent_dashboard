# Status Board Implementation Plan

> **Current milestone: 0.2.1 build 20.** The preview includes bundled event sounds, async-question waiting recognition and menu-bar window recovery with direct Pin/Unpin. Current verification: 92 core tests from build 14; build 15 passes 33 native interaction assertions. The latest user-authorized UI adds a dinosaur avatar toolbar and confirmed exit; see [avatar toolbar](verification/avatar-toolbar.md). Build 14 uses streaming metadata selection to fix reconnect loops from large conversation snapshots; see [large snapshot recovery](verification/large-snapshots.md). Focus integration remains deferred. See [current progress](verification/results.md) and [build 12 window behavior](verification/window-recovery.md).

Version: 0.1  
Date: October 23, 2026  
Status: Runnable preview 0.2.1 build 20 delivered; full-specification qualification remains in progress  
Execution condition: Authorized by the user on October 23, 2026; use the currently installed toolchain

This plan converts the [technical design](status-board-technical-design-v0.1.md) into an ordered implementation workflow. It includes deliverables, verification procedures, acceptance criteria, dependencies, and failure handling. The [product specification](status-board-product-design-v0.1.md) remains authoritative for P01–P12 and A01–A54.

The original documentation-only task did not authorize execution. The user has now requested implementation, confirmed the upgraded toolchain, and separately authorized one disposable test conversation. Original preparation was read-only; current executed evidence is recorded in verification/results.md. No system/tool upgrade or arbitrary existing-conversation modification is implied.

## 1. Execution rules

1. Read the product specification and technical design before implementation. Read applicable repository instructions and inspect existing files before changing them.
2. Execute steps in dependency order. Continue independent work if one capability is blocked, but do not build dependent behavior on an unverified assumption.
3. Record a result and evidence for each verification. `PASS` requires the stated assertions to succeed on the stated build and environment.
4. Use `NOT_RUN`, `IN_PROGRESS`, `PASS`, `FAIL`, or `BLOCKED`. Use `N/A` only for genuinely optional coverage, with a reason; it cannot waive an accepted product requirement.
5. Distinguish simulated tests, native platform tests, and real Codex integration tests. A simulated result cannot pass a real-data or system-behavior requirement.
6. Preserve the approved product semantics. If a capability cannot be implemented, report the exact limitation, evidence, and alternatives. Obtain a product decision only when a proposed alternative changes the agreed behavior.
7. Keep credentials and task content out of fixtures, logs, and reports. Use read-only observation during source discovery. Do not approve, resume, interrupt, archive, or mark real user conversations as read for testing.
8. Use synthetic fixtures for destructive or difficult failure cases. For live transition tests, use user-designated disposable conversations, or obtain explicit authorization to create those conversations. A plan document does not itself grant that authorization.
9. Have the user perform disruptive machine actions such as logout, account switching, and display removal at an appropriate time. Record such checks as pending until actually observed.
10. Once relevant checks pass, move forward. Repeat them only when a change or unresolved concern justifies doing so.

## 2. Starting baseline

The original baseline contained the approved product document and a separately stored HTML prototype. Execution has now begun; consult verification/results.md for actual completed work.

| Item | Baseline |
| --- | --- |
| Project directory | `/Users/xutao/Desktop/vibe code/Status Board` |
| Product specification | `docs/status-board-product-design-v0.1.md` |
| Technical design | `docs/status-board-technical-design-v0.1.md` |
| Target environment | macOS 15.8.1 for initial qualification |
| Installed development tools | Xcode 26.3 and Apple Swift 6.2.4 |
| Toolchain update | Optional; not a prerequisite or an action in this plan |
| Native runtime | SwiftUI, AppKit, local Swift core package |
| Real data source | Version-pinned desktop IPC, read-only account/quota helper and local inventory integrated; builds 6–7 add scoped unread/completion recovery; complete scope remains pending |

Use the current upgraded toolchain initially. If an upgrade is later requested, follow the compatibility policy in the technical design, use the Swift compiler bundled with Xcode, record the changed baseline, and rerun affected checks. Do not silently upgrade macOS or install an independent Swift toolchain.

Approved visual reference:

```text
/Users/xutao/.codex/visualizations/2026/10/23/01a169cc-3c0c-7d01-9e8f-703e5f9587fe/status-board-compact.html
```

Use its compact English layout. Exclude prototype scenario selectors, appearance sliders, simulated connection controls, and preview-only feedback from the production app.

## 3. Step sequence and gates

Statuses describe progress toward the full specification; see the current index for current evidence. Dependencies describe the original qualification gates; the user-authorized preview proceeds with partial coverage and Focus deferred; audio implemented in build 10. See [current evidence and remaining work](verification/results.md).

| Step | Outcome | Dependencies | Required verification | Current status |
| --- | --- | --- | --- | --- |
| S00 | Reproducible environment and evidence structure | Implementation requested | Environment preflight | PASS |
| S01 | Verified Codex data contract and source decision | S00 | V01–V05; G1–G4 | IN_PROGRESS |
| S02 | Native window, Focus, and lifecycle feasibility | S00; may proceed independently of S01 | V06–V08; G5–G6 and preliminary G7 | IN_PROGRESS |
| S03 | Application skeleton and frozen integration decisions | S01 and S02 gate outcomes | Build and dependency checks | IN_PROGRESS |
| S04 | Deterministic core state and event rules | S03 | V09 | IN_PROGRESS |
| S05 | Production data adapter and monitor lifecycle | S04; G1–G4 passed | V01–V05, V12 | IN_PROGRESS |
| S06 | Approved native widget and interactions | S04; G5 passed | V06, V10 | IN_PROGRESS |
| S07 | Audio, settings, Focus, and login services | S04; G6 passed | V07, V08, V11 | IN_PROGRESS |
| S08 | Integrated behavior and fault recovery | S05–S07 | V12 and integration portions of V01–V11 | IN_PROGRESS |
| S09 | Pre-release product and quality qualification | S08 | A01–A54 review, runnable cases, V13 | IN_PROGRESS |
| S10 | Installable personal-use release and final qualification | S09 | Deferred installed-bundle cases, V08, V14; final G7 | IN_PROGRESS |

For the original full specification, unresolved source/platform gates prevent a full qualification pass. The later user-authorized preview already integrates verified partial data and native behavior, so the earlier scaffold-only restriction no longer applies to that milestone. Full-specification release still requires all G1–G7 to pass for its declared scope.

### S00 — Establish the execution environment

Actions:

1. Read repository instructions, inspect the working tree, and preserve existing user changes.
2. Recheck macOS, Xcode, Swift, selected SDK, and Codex versions. Confirm actual hardware architecture and whether the shell is translated.
3. Verify that the selected SDK and compiler can build a minimal local Foundation executable. Classify environment permission errors separately from compilation failures.
4. Create `docs/verification/`, `Fixtures/`, and ignored local `artifacts/` directories as needed. Do not initialize or replace a repository solely because a `.git` directory is absent.
5. Start `docs/verification/environment.md` and `docs/verification/results.md`. Record all future gates and acceptance cases as `NOT_RUN`.

Read-only command examples, to run only when execution begins:

```sh
pwd
rg --files -g AGENTS.md -g '*.md' -g Package.swift -g project.pbxproj
sw_vers
uname -m
sysctl -n hw.optional.arm64
sysctl -n sysctl.proc_translated
xcode-select -p
xcrun swift --version
xcodebuild -version
xcrun --sdk macosx --show-sdk-path
```

An absent `sysctl.proc_translated` key is a possible result, not a reason to invent a hardware architecture.

Deliverables: environment report, evidence index, reproducible preflight command list.

Pass condition: the selected compiler can compile and run a minimal executable with the intended SDK; environment and architecture are explicit. Version output alone is insufficient.

Failure handling: resolve a concrete setup problem or record a blocker. An IDE upgrade is not the default response to a sandbox or cache-directory warning.

### S01 — Prove the Codex data contract

Actions:

1. Capture the installed CLI help and protocol schema into local artifacts. Start with the normal schema; enable experimental schema output only if a specific required capability justifies it.
2. Inventory candidate read-only sources and their account scope. Check whether a documented connection reaches the actual desktop runtime.
3. Build a small Swift command-line probe in `Probes/CodexProbe/` with bounded execution time, JSON-RPC framing where applicable, request IDs, cancellation, and redacted output.
4. Validate quota and account identity with V01, task scope with V02, unread behavior with V03, event continuity with V04, and health behavior with V05.
5. Record actual field mappings, null handling, source versions, pagination, ordering, and lifecycle behavior in `docs/verification/codex-integration.md`.
6. Record the selected source and rejected alternatives in a short decision record. Include the reason a source can satisfy the desktop scope rather than merely returning some threads.

Observed CLI commands available for future inspection:

```sh
CODEX_BIN='/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex'
"$CODEX_BIN" --version
"$CODEX_BIN" app-server --help
"$CODEX_BIN" app-server proxy --help
"$CODEX_BIN" app-server generate-json-schema --help
"$CODEX_BIN" app-server generate-json-schema --out artifacts/protocol/installed
```

Re-resolve `CODEX_BIN` if the application moved. Inspect local help before using any new flag. Do not start an unattended server or attach to an inferred socket merely because a related command exists.

Deliverables: probe source, sanitized fixtures, capability report, source-to-domain mapping, G1–G4 results.

Pass condition: G1–G4 each have real-source evidence, including actual desktop unread changes and a sound-safe observation boundary.

Failure handling: retain successful independent capabilities. For example, quota success with unread failure does not pass the task widget. Report the blocked contract and continue independent native feasibility work.

### S02 — Prove native macOS behavior

Actions:

1. Create an isolated native probe bundle in `Probes/NativeProbe/`; use a distinct bundle identifier from the final app.
2. Implement only the minimum panel needed to test icon/card forms, dragging, desktop/pinned levels, activation, full-screen applications, Spaces, and screen removal.
3. Test a public Focus integration under V07. Document authorization, entitlements, signing, status freshness, and unknown-state behavior.
4. Test three short audio samples and a serial queue. This establishes playback feasibility, not production event semantics.
5. Test login-item registration feasibility from a stable probe install path, with the user's participation for a real login test. Remove only probe-owned registration after the test.
6. Write `docs/verification/native-feasibility.md` with exact window flags, signing settings, and evidence.

Deliverables: native probe source, screenshots or recordings, G5/G6 results, preliminary G7 findings.

Pass condition: V06 and V07 satisfy the accepted behavior. Login registration has a viable implementation path; final G7 still requires the release bundle in S10.

Failure handling: do not substitute an always-frontmost extreme window level, permanently muted audio, or a notification banner for the specified behavior. Capture the failed combination and identify the required product decision if no compatible solution exists.

### S03 — Create the application and freeze implementation choices

Actions:

1. Create `StatusBoard.xcodeproj` with a shared `StatusBoard` scheme, an app target, platform test targets, and macOS 15.0 deployment target.
2. Create the local `Packages/StatusBoardCore` package with Swift 6 language mode and Swift Testing.
3. Define protocol boundaries for Codex observation, clocks, audio, Focus, persistence, Codex activation, and login registration.
4. Compose services at the app entry point. Give the app a stable bundle identifier and accessory-app lifecycle.
5. Add the planned command scripts and document their contracts. Keep build output in ignored local directories.
6. Freeze the verified source, event boundary, window policy, Focus integration, signing approach, and initial refresh parameters in the technical design's decision section.

Deliverables: buildable skeleton, shared scheme, core package, service interfaces, build/test scripts, updated decision records.

Pass condition: the app builds and launches, the package test runner works, and production UI has no dependency on fixture controls. All unresolved feasibility gates are explicitly visible.

### S04 — Implement and test the core rules

Actions:

1. Implement domain models, task normalization, scope filtering, quota normalization, and timestamp formatting.
2. Implement count reduction independently from alert classification.
3. Implement event identity, deduplication, generation changes, bootstrap suppression, and queue eligibility using injected clocks and services.
4. Implement atomic snapshot serialization and version validation behind a storage protocol.
5. Add deterministic tests for V09 and the synthetic dataset in Section 6.

Deliverables: core code and tests, normalized fixtures, test results.

Pass condition: all V09 assertions pass without live Codex, audio hardware, wall-clock sleeps, or network access. Tests cover behavior and boundary cases rather than merely repeating implementation branches.

### S05 — Implement the live adapter and monitoring lifecycle

Actions:

1. Implement only the source selected in S01 behind `CodexAdapter`.
2. Add connection generations, complete-snapshot handling, pagination, replay filtering, and periodic reconciliation.
3. Implement unified connection health, retry grace, silent recovery, explicit desktop shutdown, and account switching.
4. Persist only valid account-bound quota snapshots and complete-sync timestamps.
5. Add adapter contract tests using sanitized wire fixtures. Re-run the real-source assertions against the production adapter.

Deliverables: production adapter, monitor coordinator, contract tests, timing measurements, updated G1–G4 evidence.

Pass condition: V01–V05 pass through the production implementation. An unavailable data field remains unavailable; an old connection cannot update the current account.

### S06 — Implement the approved widget

Actions:

1. Implement the compact icon/card views and native material using the accepted visual reference.
2. Add the header controls in order: gear, Pin, collapse. Bundle the approved icon locally.
3. Implement both forms, persistent expansion, Pin independence, drag/click distinction, valid-position restoration, and one-instance behavior.
4. Add accurate connected, disconnected, saved-quota, and empty states; implement hover/focus access to timestamps.
5. Implement the three-item dropdown and Codex activation from task counts.
6. Add accessibility labels and keyboard behavior. Capture comparison screenshots on light, dark, and complex backgrounds.

Deliverables: native UI, panel controller, focused UI tests, visual evidence.

Pass condition: V06 and V10 pass. No task names, removed subtitle, collapsed Done badge, or design-only controls appear.

### S07 — Implement sounds and system settings

Actions:

1. Integrate three fixed short sounds and a playback-completion-driven serial queue.
2. Apply suppression before enqueueing and immediately before playback. Cancel pending sounds on mute, Focus, disconnect, sleep, account change, and quit.
3. Connect the verified Focus provider, including authorization changes and unknown-state handling.
4. Implement persisted mute preference, system-reconciled login startup, and quit cleanup.
5. Verify sound distinctions by listening and queue behavior through an injected audio driver.

Deliverables: audio service, Focus provider, settings services, three bundled sound files, verification evidence.

Pass condition: V07, V08's non-login-cycle checks, and V11 pass. The default sound behavior works under a valid Focus state; a permanently unknown provider cannot pass by suppressing everything.

### S08 — Integrate and exercise recovery

Actions:

1. Wire the production services and run controlled real transitions with all UI and audio paths active.
2. Inject timeouts, malformed responses, partial pages, duplicate/reordered events, source-version mismatch, and account-generation races through test adapters.
3. Verify startup, wake, reconnection, cache corruption, clock/time-zone changes, and quit while audio is queued.
4. Measure refresh delays and finalize the initial tuning values in the technical design.
5. Run V12 and update results for real integration portions of V01–V11.

Deliverables: integrated app, fault-injection results, finalized timing policy, regression fixes.

Pass condition: faults neither fabricate counts nor replay historical audio. Recovery produces a coherent current snapshot and subsequent new events work normally.

### S09 — Qualify against the product specification

Actions:

1. Review every A01–A54 case using the traceability table in Section 7. Execute all cases runnable against the release candidate; schedule final installed-bundle checks, including A48, for S10.
2. Run the quality measurements in V13 on the target host after warm-up.
3. Record real audio, window, Focus, and unread results separately from fixture-based results.
4. Fix material failures and rerun the affected cases. Record unavailable hardware or user-assisted scenarios as `BLOCKED`, not assumed passes.
5. Review the final app for exact English copy, no prototype controls, and correct default preferences.

Deliverables: complete acceptance matrix, timing/resource report, known-limitations record, release-candidate build identity.

Pass condition: every case runnable before final installation passes and all quality targets are measured. Installed-bundle checks remain explicitly `NOT_RUN` with S10 as their owner; this is not release approval. A missed engineering target requires an explicit documented disposition; an accepted product behavior requires a product decision before being changed or waived.

### S10 — Package and hand off

Actions:

1. Build the release configuration with the recorded signing arrangement and stable bundle identity.
2. Stage the `.app` and install it at the agreed stable local path when execution is authorized. Preserve an existing installation for rollback.
3. Verify that the packaged app works independently of Xcode and the source checkout.
4. Re-run login startup, quit isolation, default/relaunch preferences, and Focus behavior using the installed release bundle.
5. Produce build/run instructions, an artifact checksum, compatibility details, and the final evidence index.

Deliverables: installable `.app`, release verification report, instructions, checksum, documented limitations.

Pass condition: V08 and V14 pass on the final bundle, G1–G7 are passed, and no required acceptance case remains `NOT_RUN`, `FAIL`, or `BLOCKED`.

## 4. Planned command interface

Create the scripts below during S03. The environment, core-test and app-build scripts now exist and have run; native-test and release-verification scripts remain planned. See verification/results.md for actual evidence.

| Script | Required behavior | Successful exit means |
| --- | --- | --- |
| `scripts/verify-environment.sh` | Report tool versions and SDK; run a minimal compiler smoke check | Tools are usable for this build |
| `scripts/test-core.sh` | Run deterministic core tests using a local scratch directory | Core assertions passed |
| `scripts/build-app.sh Debug` | Build the shared app scheme and print the actual artifact path | Compilation and bundle construction succeeded |
| `scripts/run-native-tests.sh` | Run selected native tests in a supported interactive session | Reported native assertions passed; manual checks remain separate |
| `scripts/verify-release.sh PATH_TO_APP` | Verify bundle metadata, resources, architecture, signature, and launch prerequisites | Static release checks passed; no implied login/Focus success |

Representative build commands after the project exists:

```sh
xcrun swift test --package-path Packages/StatusBoardCore --scratch-path .build/core

xcodebuild -project StatusBoard.xcodeproj \
  -scheme StatusBoard \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .build/xcode \
  build CODE_SIGNING_ALLOWED=NO
```

The unsigned build is a compilation check only. Use the separately documented signing configuration for Focus permissions, UI automation, installed-app behavior, and login-item qualification. Do not enable automatic provisioning or download tools without an actual need and appropriate authorization.

## 5. Verification procedures

Each procedure produces a report under `docs/verification/` and local artifacts where needed. Reports must identify the actual build, operating system, source version, execution mode, and observation time.

### V01 — Account identity and quota

- Compare the adapter with the same account's Codex usage display within one refresh interval. Record each actual window, remaining value, and reset time.
- Validate a source with one window, two windows, an unfamiliar duration, and a missing reset time using sanitized or synthetic contract fixtures.
- Test 41%, 40%, 21%, 20%, 40.9%, 20.9%, 0%, and 100%; verify the documented rounding and color policy.
- Test missing, negative, non-finite, and greater-than-100 inputs. Invalid values must show unavailable data rather than fabricated exhaustion.
- With user assistance, verify that an account switch clears the previous account's values and timestamp before new data appears. Test a delayed old-account response as a deterministic race.
- Pass when real values match after the documented integer conversion, valid source cycles are preserved, and account isolation holds. An account without an available quota response remains unavailable; it does not prove quota integration.

### V02 — Real task states and scope

- Use designated test conversations to observe execution, ordinary waiting, continuation, completion, stopped error, automatic retry, and intentional stop.
- Compare the full unarchived top-level scope with the desktop account, following every page. Include applicable CLI/cloud-origin conversations and multiple desktop windows.
- Observe a parent with subagent work. Verify that the same top-level conversation contributes at most one count and a child contributes no separate count.
- Verify removal from scope when a designated test conversation is archived by the user. Do not archive unrelated conversations.
- Pass when all required states and applicable sources map correctly, with zero duplicate top-level counts. Lack of a cloud example must be recorded as unverified coverage, not a successful cloud test.

### V03 — Actual Done and unread semantics

1. Complete a designated conversation while it is unread; observe `Done + 1`.
2. Expand/collapse the widget and click its Done region; confirm Status Board does not write a read flag or clear its count itself.
3. Read that result in Codex; observe `Done - 1` within the propagation target.
4. Run another turn in the same conversation; the old Done contribution disappears while processing starts.
5. Observe a completion already marked read by Codex; Done remains unchanged, while a genuinely new event is still eligible for its sound.
6. Repeat with at least two conversations and after restarting the monitor.

Pass only with an identified source field or event that tracks Codex's real read state. Time elapsed, foreground-app detection, and a local unread ledger are not sufficient substitutes.

### V04 — Event identity and bootstrap boundary

- Replay each event ten times; expect one alert decision and one count contribution.
- Produce two separate waiting episodes in one run, plus two different runs in one conversation; expect distinct event identities and the specified separate sounds.
- Start with historical unread and waiting items; restore counts without sound.
- Disconnect, complete work while disconnected, and reconnect; restore current counts without catch-up sound. A new post-recovery event must sound normally.
- Inject an event during the snapshot/subscription race, an out-of-order event, and a delayed old-generation event. Verify the documented source boundary and no rollback.
- If polling is proposed, demonstrate two meaningful transitions occurring between polls. Pass only if the source preserves enough event history to avoid losing them.

Pass when every sound decision can be explained by a stable occurrence identity and a proven live boundary. A plausible timestamp heuristic alone does not pass.

### V05 — Connection health and complete synchronization

- Inject a single failed read followed by success within the grace period; do not flicker into false disconnection or emit a false event.
- Fail only the quota path, then only the task/read-state path. After the critical failure threshold, both must yield the single disconnected UI.
- Close Codex through an appropriate user-controlled test. Confirm the explicit-shutdown behavior, frozen quota, `—` task counts, and absence of a stale `!`.
- Inspect `Last updated`: it advances only after a complete successful sync, not on an event-only update, partial result, tooltip, failure, or redraw.
- Restore a valid source and verify silent bootstrap. A frozen reset deadline must not refill quota.

Pass when the measured timing matches the finalized policy and all paths produce one coherent public connection state.

### V06 — Native window matrix

Test both forms with Pin off/on against ordinary and fullscreen applications. Repeat across at least two Spaces. Check that task events do not steal focus, expand, raise, or move the widget.

Test dragging versus clicking, reopening, different screen scale factors when available, and removing the display containing the widget. Confirm one visible instance, valid frame clamping, and stable Pin/form state.

Pass when the exact matrix satisfies A01–A05, A21, and A35–A40. Record the tested fullscreen applications and display setup. A screenshot of an ordinary floating panel does not establish fullscreen or Spaces support.

### V07 — Focus and authorization

Test Focus off/on while the app is foreground and background, including a sound already queued. Test status sharing disabled, permission denied, permission revoked, and a Focus profile that allows the app through.

For each case, record the observed provider value, its age, permission state, expected product behavior, and actual audio. Confirm that visuals continue and old sounds do not play after suppression ends.

Pass only if the provider reliably implements the required Focus rule and ordinary audio works when permitted. Unknown status must have an explicit diagnostic and cannot be treated as proof that Focus is off. If public APIs cannot distinguish a required situation, G6 is blocked pending a product decision.

### V08 — Login and application lifecycle

- Verify both settings default to unchecked on a clean preference store.
- Toggle login startup and reconcile the checkbox with the system's actual registration state, including failure and approval-required outcomes.
- With the user's participation, perform a real logout/login with startup enabled, then disabled. Verify the correct launch behavior and silent historical baseline.
- Change preferences and window position, quit, and relaunch; verify restoration.
- Quit while Codex is processing and audio is queued; confirm the widget exits, audio stops, and Codex work continues.
- Launch the application twice; confirm only one widget and one active monitor.

Pass on the final signed bundle at its stable install path. A registration API returning success without a login cycle is insufficient for A48.

### V09 — Deterministic domain tests

Use injected clocks and synthetic fixtures to test counts, scopes, current-run read state, duplicate IDs, source revisions, quota boundaries, time formatting, bootstrap suppression, reconnect behavior, event consumption during mute, and account-generation isolation.

Exercise corrupt/unsupported cache versions and atomic write failure. Verify that a failed write preserves the previous valid snapshot and does not change live counts.

Pass with all assertions deterministic and no real network or audible playback. Include tests for data absence and invalid inputs, not just happy paths.

### V10 — UI, copy, and accessibility

- Compare compact dimensions, glass appearance, header order, smaller quota text, and absent subtitle with the approved reference.
- Verify the exact English labels and that `Waiting for operation` is not truncated or renamed.
- Verify the collapsed `!` location and absence of processing/Done badges.
- Exercise menu selection, repeated gear click, outside click, Escape, and card collapse. The card must remain expanded when only the menu closes.
- Verify unavailable values, disconnected saved-usage wording, tooltip dates, missing-time placeholders, and keyboard access to the same information.
- Check light/dark/complex backgrounds, reduced transparency, and screen-reader names, including the unread meaning of Done.

Pass when functionality and legibility hold in the tested native states. Do not demand a pixel-identical material effect across different backgrounds.

### V11 — Audio delivery and suppression

- Listen to one completion, one ordinary waiting event, and one stopped error; all three must be distinguishable.
- Queue ten distinct mixed events; verify ten sequential playback starts and no overlap, with a fake driver for exact assertions and a short real listening check.
- Replay duplicates; verify no extra sound. Verify read completions still sound when newly observed and eligible.
- Enter mute and Focus while sounds are queued; pending sounds are consumed and cancelled. Leaving suppression must not replay them.
- Test system mute/volume, audio-device failure, foreground Codex activity, and quitting during playback.

Pass when eligible new events play once, suppression never creates a catch-up queue, and playback failures never produce repeated retries.

### V12 — Recovery and fault injection

Cover sleep/wake, transport termination, request timeout, malformed schema, missing required fields, partial pagination, replay, out-of-order responses, account switch during a request, corrupt cache, and time-zone changes.

For every case assert visible counts, quota, timestamp, audio decisions, and retained preferences. Old generations must not overwrite new state. Unknown data must not appear as zero. Restart and wake restore a silent baseline.

Pass when all scenarios recover or enter the defined disconnected state without a crash, stale-account leak, historical audio, or mutation of Codex work.

### V13 — Performance and stability

Measure a release build on the recorded host using the technical design's targets:

- 50 local UI actions for p95 interaction latency.
- At least 20 real task/read transitions for source-to-widget delay, with the method of observing the source timestamp recorded.
- Empty-queue event-to-audio delay separately from intentional queue waiting.
- A quota change across a normal refresh interval; use a contract fixture for controlled timing if no real change occurs, and keep real-source freshness evidence separate.
- 10 minutes of idle CPU and memory after warm-up, including incremental owned helpers.
- A 2-hour ordinary-use session with event bursts, a disconnect, wake, and mute/Focus transitions. Record crashes, queue length, and memory drift.

Pass when measurements meet the stated targets. Do not substitute inferred performance or debug-build observations for release-build measurements.

### V14 — Release artifact

- Build the release app and record its version, checksum, architecture, minimum OS, signing identity, and source revision or source manifest.
- Inspect bundled icon and audio resources; verify no runtime dependency on the HTML prototype or a development server.
- Launch from the stable install path with Xcode closed and without relying on the repository as the working directory.
- Re-run the final-bundle Focus, login, quit-isolation, and preference-restoration checks.
- Verify that the documented build commands recreate a runnable artifact from a clean build directory.

Pass when the artifact is usable on the declared host, its installation and build steps are reproducible, and all required evidence refers to the final build or demonstrably unchanged components.

## 6. Required deterministic fixtures

The base fixture contains the following records for account A:

| Record | State | Expected contribution |
| --- | --- | --- |
| T1 | Top-level processing | Processing +1 |
| T1 duplicate | Same conversation in another window | None beyond T1 |
| T2 | Waiting for approval | Waiting +1 |
| T3 | Failed and stopped, needs intervention | Waiting +1 |
| T4 | Latest run completed and unread | Done +1 |
| T5 | Latest run completed and read | None |
| T6 | Intentionally stopped | None |
| T7 | Archived, completed and unread | None |
| T8 | Child of T1 | None separately |
| B1 | Record for a different account | None in account A |

Expected aggregate: **1 processing, 2 Waiting for operation, 1 Done**. The collapsed icon shows one `!`, never a number. Starting a new run in T4 changes the aggregate to **2 / 2 / 0**.

Additional fixture sequences must include: repeated waiting in the same run; successful completion already read; error versus intentional interruption; automatic retry; partial pages; unavailable unread state; duplicate completion; bootstrap race; reconnect replay; old-account responses; invalid quota; reset while offline; and corrupt cache.

## 7. Product acceptance traceability

The original product document contains the full scenario text. This table identifies the primary verification and execution step for every case. All results initially remain `NOT_RUN`.

| Case | Required outcome | Verification | Step |
| --- | --- | --- | --- |
| A01 | Explicit expand and collapse preserve data | V06, V10 | S06 |
| A02 | Outside clicks keep the card expanded | V06, V10 | S06 |
| A03 | Unpinned widget can be covered | V06 | S02, S06 |
| A04 | Pinned widget satisfies ordinary/fullscreen behavior | V06 | S02, S06 |
| A05 | Form changes preserve Pin | V06 | S06 |
| A06 | Done-only state produces no collapsed badge | V09, V10 | S04, S06 |
| A07 | Waiting produces a top-right exclamation mark only | V09, V10 | S04, S06 |
| A08 | Last resolved wait removes the exclamation mark | V02, V10 | S05, S06 |
| A09 | Concurrent categories show accurate separate counts | V02, V09 | S04, S05 |
| A10 | New completion sounds once and counts if unread | V03, V04, V11 | S08 |
| A11 | Repeated observation does not duplicate sound or count | V04, V09 | S04, S05 |
| A12 | Different completions each sound | V04, V11 | S07, S08 |
| A13 | Persistent waiting sounds only on entry | V04, V11 | S07, S08 |
| A14 | Foreground Codex activity does not suppress eligible sound | V11 | S08 |
| A15 | Launch and wake restore history silently | V04, V12 | S08 |
| A16 | Widget interaction does not mark results read | V03, V10 | S05, S06 |
| A17 | Actual Codex reading reduces Done | V03 | S01, S05 |
| A18 | Low quota changes color without an alert | V01, V11 | S05, S07 |
| A19 | Reset time appears on hover only | V01, V10 | S06 |
| A20 | Disconnect freezes quota and hides task counts | V05, V12 | S05, S08 |
| A21 | A hidden unpinned widget does not raise on alert | V06, V11 | S08 |
| A22 | Approved English copy and compact layout | V10 | S06 |
| A23 | A new run replaces the old Done contribution | V03, V09 | S04, S05 |
| A24 | Completion history never accumulates into Done | V03, V09 | S04, S05 |
| A25 | Ordinary waiting and stopped error share count but have distinct sounds | V02, V11 | S05, S07 |
| A26 | Retry remains processing; intentional stop is silent | V02, V09, V11 | S08 |
| A27 | Cross-window duplicates and subagents do not inflate counts | V02, V09 | S01, S05 |
| A28 | Applicable CLI/cloud sources are covered; archives excluded | V02 | S01, S05 |
| A29 | Already-read new completion can sound without increasing Done | V03, V11 | S08 |
| A30 | 41/40/21/20 percent boundaries are correct | V01, V09 | S04, S05 |
| A31 | Transient failures retry without false state events | V05, V12 | S05, S08 |
| A32 | Shutdown or sustained failure causes unified disconnect | V05 | S05, S08 |
| A33 | Offline events restore silently after reconnect | V04, V12 | S08 |
| A34 | Separate waiting episodes each alert once | V04, V11 | S08 |
| A35 | Clean first launch is collapsed and unpinned | V06, V08 | S06, S08 |
| A36 | Relaunch restores form, Pin, and valid position | V06, V08 | S08 |
| A37 | Dragging saves position without click activation or snapping | V06 | S06 |
| A38 | One widget stays on its chosen screen | V06 | S02, S06 |
| A39 | Display removal restores a visible frame | V06 | S02, S06 |
| A40 | Spaces preserve one widget and the Pin contract | V06 | S02, S06 |
| A41 | Gear opens the three items in the approved order | V10 | S06 |
| A42 | Default toggles and persistence are correct | V08, V10 | S07, S08 |
| A43 | Menu dismissal preserves the expanded card and usable focus | V10 | S06 |
| A44 | Concurrent distinct sounds play serially once each | V11 | S07 |
| A45 | Mute/Focus suppress audio but preserve visual updates | V07, V11 | S07, S08 |
| A46 | Entering suppression cancels queued sounds without catch-up | V07, V11 | S07 |
| A47 | Quit stops only Status Board | V08, V12 | S08, S10 |
| A48 | Enabled/disabled login startup works after real login | V08 | S10 |
| A49 | No cache or valid data displays unavailable values | V01, V09, V10 | S04, S06 |
| A50 | Offline reset deadline does not refill cached quota | V05, V09 | S05, S08 |
| A51 | Account switches remove all old-account display data | V01, V12 | S05, S08 |
| A52 | Both time tooltips use local date/time and are not persistent | V01, V10 | S06 |
| A53 | Failed reads and redraws do not advance Last updated | V05, V09 | S05, S08 |
| A54 | Unknown times display a dash | V01, V09, V10 | S04, S06 |

## 8. Evidence and completion records

At implementation time, create the following reports:

| Report | Contents |
| --- | --- |
| `docs/verification/environment.md` | Machine, architecture, tools, SDK, source versions, signing context |
| `docs/verification/codex-integration.md` | Source decision, actual field mapping, G1–G4 evidence, timing policy |
| `docs/verification/native-feasibility.md` | Window matrix, Focus behavior, permissions, preliminary lifecycle findings |
| `docs/verification/results.md` | S00–S10, G1–G7, V01–V14, and A01–A54 statuses with evidence links |
| `docs/verification/performance.md` | Measurement method, samples, environment, actual values, target comparison |
| `docs/verification/release.md` | Final bundle identity, checksum, install location, signing, final lifecycle results |

Each verification entry must include:

```text
Verification ID:
Build or source revision:
Environment and source version:
Execution mode: deterministic / native / real Codex / user-assisted
Preconditions:
Actions:
Expected result:
Observed result:
Evidence paths:
Status:
Remaining issue and next action:
```

A screenshot can demonstrate appearance or window placement, but cannot prove unread-source correctness, event deduplication, or successful login startup on its own. Test-runner success cannot certify an unexecuted manual scenario.

## 9. Release completion criteria

The first release is complete when:

- G1–G7 pass on the declared environment and selected data-source version.
- A01–A54 have recorded passing outcomes, including real unread synchronization, Focus suppression, fullscreen/Spaces behavior, and a real login cycle.
- Core and adapter tests pass; native and real-source evidence are linked separately.
- Performance and stability targets are measured and any engineering deviations have an explicit disposition.
- The installed release bundle works independently of the development checkout, preserves preferences, and leaves Codex tasks running on quit.
- Build instructions, artifact checksum, compatibility scope, and known limitations are delivered.

Release criteria remain pending. The execution evidence index, not this planned sequence, records what has actually run.

## 10. Resuming execution later

When implementation resumes, start from the build 20 baseline and remaining-work categories in [the current index](verification/results.md). Do not restart completed preview work or treat archived scaffold-only restrictions as current blockers. Revalidate earlier evidence only when the environment, source or affected behavior has changed. Record evidence as each remaining item is completed.

Pause only the dependent work when an actual gate fails. Explain the failed contract and the evidence needed to proceed; continue useful independent work. If the required remedy changes a confirmed product rule, present a concrete alternative for the user's decision before implementing that change.

## Historical implementation review — build 7

The native application and version-pinned adapter are integrated and packaged. Builds 4–7 implement read reconciliation, connection readiness without loaded owners, silent unloaded unread recovery and retained numeric counts after the last unread is read. Latest recorded validation is 48 passing tests; this review itself changes documentation only.

Remaining implementation: audio playback/queue and reliable Focus integration (deferred by user), complete local/remote/cloud runtime coverage, compatibility beyond build 21477 and formal distribution. Remaining qualification: actual login cycles, real wait/error/retry/account-switch scenarios, full native/accessibility matrix, broader recovery, performance/stability and final release acceptance. Settings and login registration are implemented; they must not be listed as absent.

Build 10 supersedes the audio-deferred status in this historical review. The [current index](verification/results.md) is the progress baseline. The [historical checkpoint](verification/results-pre-preview.md) retains early feasibility evidence and prior step/case tables without applying their superseded scaffold-only restrictions.
