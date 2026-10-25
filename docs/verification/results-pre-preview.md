# Historical implementation and qualification record — before the usable preview

> Archived during the October 23, 2026 documentation review. The tables below describe the earlier full-specification checkpoint, not build 7. Statements that the app is only a scaffold, lacks an adapter/login registration, or must keep connected counters disabled are superseded by the user-authorized preview. Use [current status](results.md) for remaining work. This archive preserves prior evidence and does not impose current execution restrictions.

## Previous full-specification baseline

Updated October 23, 2026 (America/New_York). This index is the execution record; the original plan remains the requirement, not evidence of completion.

Current outcome: **implementation started; release blocked on data-source/event feasibility**. The user approved use of the updated toolchain and one disposable test conversation. The original product semantics have not been weakened.

The independent scaffold compiled successfully with the shared Xcode scheme. The 28 implemented Swift Testing tests passed. Native construction and temporary-foreground smoke passed. The user confirmed pinned fullscreen/two-Spaces visibility and click-to-front behavior. Real runtime/unread/read transitions were captured by Python and Swift observers; the full Focus capability probe is blocked by OS signature validation. These results do not pass the full integration gates.

## Steps

| Step | Status | Evidence / remaining work |
| --- | --- | --- |
| S00 | PASS | Current toolchain checked; Foundation compile/run passed. |
| S01 | IN_PROGRESS | Swift private IPC observer receives real local runtime; vnode invalidation fixes missed read updates. Complete account scope and real wait/error episodes pending. |
| S02 | IN_PROGRESS | User-confirmed window subset passes; Focus capability execution blocked by signing; full matrix pending. |
| S03 | IN_PROGRESS | Shared Xcode scheme + local Swift package build; scaffold only, no frozen integration decisions or platform test targets. |
| S04 | IN_PROGRESS | Independent domain subset implemented; 28 Swift Testing tests pass; V09 not complete. |
| S05 | BLOCKED | No production adapter selected; do not wire private metadata discovery into the app. |
| S06 | BLOCKED | Native widget depends on G5; current app is an unavailable-data scaffold, not the approved widget. |
| S07 | BLOCKED | Audio/Focus/login integration waits for feasibility; no sounds or login registration implemented. |
| S08 | NOT_RUN | Requires selected adapter and platform services. |
| S09 | NOT_RUN | No release candidate. |
| S10 | NOT_RUN | No qualified release or installation. |

S03/S04 contain independent work only, as allowed when gates are unresolved. Neither step is marked PASS. The inspected private runtime ordering is tested in an isolated experimental stream reducer, not connected to production counts or sounds.

## Gates

| Gate | Status | Evidence / remaining work |
| --- | --- | --- |
| G1 | IN_PROGRESS | Real account/quota reads succeeded; full identity/isolation and comparison checks pending. |
| G2 | IN_PROGRESS | Separate desktop coordination IPC works for loaded local threads; full account-bound scope remains unqualified. |
| G3 | IN_PROGRESS | Several user-confirmed reads; Swift vnode refresh verified. Whole-scope/run/account tests pending. |
| G4 | IN_PROGRESS | Real per-thread snapshot/delta revisions verified; durable waits and full bootstrap/reconnect contract remain unqualified. |
| G5 | IN_PROGRESS | User-confirmed pinned fullscreen/two Spaces and click-to-front pass; display/removal and full matrix pending. |
| G6 | BLOCKED | Authorized minimal probe stays false with sharing off/on. Full entitlement path prepared but OS rejects ad-hoc signature; valid capability signing required. |
| G7 | NOT_RUN | Stable signed install, login cycles and quit isolation pending. |

## Verification procedures

| Verification | Status | Evidence / remaining work |
| --- | --- | --- |
| V01 | IN_PROGRESS | Real identity/quota field presence confirmed; comparisons/isolation pending. |
| V02 | IN_PROGRESS | One designated processing/completion seen; complete scope and waiting/error/retry cases pending. |
| V03 | IN_PROGRESS | One real unread-to-read transition observed after user reading; full procedure incomplete. |
| V04 | IN_PROGRESS | Real runtime revision boundary and silent baseline tested; whole-source continuity and real short waits pending. |
| V05 | NOT_RUN | Unified monitor health coordinator not implemented. |
| V06 | IN_PROGRESS | Smoke plus user-confirmed window subset; remaining matrix in native report. |
| V07 | BLOCKED | Authorization succeeds via Launch Services, but full Focus prerequisites and semantics remain unqualified. |
| V08 | NOT_RUN | Status read only; no registration or login-cycle validation. |
| V09 | IN_PROGRESS | 28 tests pass; coordinator recovery, injected write failure and serial playback still required. |
| V10 | NOT_RUN | Not executed against an integrated production build. |
| V11 | NOT_RUN | Not executed against an integrated production build. |
| V12 | NOT_RUN | Not executed against an integrated production build. |
| V13 | NOT_RUN | Not executed against an integrated production build. |
| V14 | NOT_RUN | Not executed against an integrated production build. |

## Executed deterministic checks

Build: source hashes in `source-manifest.json`. Environment: Swift 6.2.4 / macOS 15.8.1. Mode: deterministic, no live network or audio.

Command: `scripts/test-core.sh`. Observed: **28 tests passed**, including parameterized quota/Focus cases. Evidence: `artifacts/preflight/core-tests-stream.txt`.

Assertions cover the approved 1/2/1 aggregate, cross-window/subagent/account filtering, new run replacing Done, complete-vs-partial/unknown snapshots, current-run unread association, stale revisions/archive tombstones, equal-revision conflicts, waiting badge rules, all quota boundaries, invalid numbers, actual cycle labels, historical event suppression, duplicates, separate waiting identities, mute/Focus consumption, generation changes, already-read completion alerts, timezone formatting, corrupt/unsupported caches and account isolation. Cache tests cover rejection of invalid writes preserving the previous snapshot; an injected filesystem write failure is still pending.

Eleven additional stream tests cover fragmented/coalesced framing, content filtering, text-only deltas, two-phase completion/read updates, same-revision read refresh, gaps and silent resync, owner change, atomic malformed-patch rejection, stable short-wait IDs, unknown requests, canonical tail coverage, and heartbeat suppression.

This does not certify a production event queue, event-source ordering, an actual Focus provider, all V09 cases, or any manual acceptance scenario.

## Product acceptance

All A01–A54 remain unqualified on the product. IN_PROGRESS means some independent evidence exists, not acceptance. The required procedures and steps remain as mapped in the implementation plan.

| Case | Status | Current evidence |
| --- | --- | --- |
| A01 | NOT_RUN | Not exercised on an integrated product. |
| A02 | NOT_RUN | Not exercised on an integrated product. |
| A03 | NOT_RUN | Not exercised on an integrated product. |
| A04 | NOT_RUN | Not exercised on an integrated product. |
| A05 | NOT_RUN | Not exercised on an integrated product. |
| A06 | IN_PROGRESS | Independent domain evidence only; product/native/integration checks pending. |
| A07 | IN_PROGRESS | Independent domain evidence only; product/native/integration checks pending. |
| A08 | NOT_RUN | Not exercised on an integrated product. |
| A09 | IN_PROGRESS | Independent domain evidence only; product/native/integration checks pending. |
| A10 | NOT_RUN | Not exercised on an integrated product. |
| A11 | IN_PROGRESS | Independent domain evidence only; product/native/integration checks pending. |
| A12 | NOT_RUN | Not exercised on an integrated product. |
| A13 | NOT_RUN | Not exercised on an integrated product. |
| A14 | NOT_RUN | Not exercised on an integrated product. |
| A15 | NOT_RUN | Not exercised on an integrated product. |
| A16 | NOT_RUN | Not exercised on an integrated product. |
| A17 | IN_PROGRESS | One real desktop reading observed; full V03 pending. |
| A18 | NOT_RUN | Not exercised on an integrated product. |
| A19 | NOT_RUN | Not exercised on an integrated product. |
| A20 | NOT_RUN | Not exercised on an integrated product. |
| A21 | NOT_RUN | Not exercised on an integrated product. |
| A22 | NOT_RUN | Not exercised on an integrated product. |
| A23 | IN_PROGRESS | Independent domain evidence only; product/native/integration checks pending. |
| A24 | IN_PROGRESS | Independent domain evidence only; product/native/integration checks pending. |
| A25 | IN_PROGRESS | Independent domain evidence only; product/native/integration checks pending. |
| A26 | NOT_RUN | Not exercised on an integrated product. |
| A27 | IN_PROGRESS | Independent domain evidence only; product/native/integration checks pending. |
| A28 | NOT_RUN | Not exercised on an integrated product. |
| A29 | IN_PROGRESS | Independent domain evidence only; product/native/integration checks pending. |
| A30 | IN_PROGRESS | Independent domain evidence only; product/native/integration checks pending. |
| A31 | NOT_RUN | Not exercised on an integrated product. |
| A32 | NOT_RUN | Not exercised on an integrated product. |
| A33 | NOT_RUN | Not exercised on an integrated product. |
| A34 | NOT_RUN | Not exercised on an integrated product. |
| A35 | NOT_RUN | Not exercised on an integrated product. |
| A36 | NOT_RUN | Not exercised on an integrated product. |
| A37 | NOT_RUN | Not exercised on an integrated product. |
| A38 | NOT_RUN | Not exercised on an integrated product. |
| A39 | NOT_RUN | Not exercised on an integrated product. |
| A40 | NOT_RUN | Not exercised on an integrated product. |
| A41 | NOT_RUN | Not exercised on an integrated product. |
| A42 | NOT_RUN | Not exercised on an integrated product. |
| A43 | NOT_RUN | Not exercised on an integrated product. |
| A44 | NOT_RUN | Serial playback queue is not implemented. |
| A45 | IN_PROGRESS | Independent domain evidence only; product/native/integration checks pending. |
| A46 | IN_PROGRESS | Independent domain evidence only; product/native/integration checks pending. |
| A47 | NOT_RUN | Not exercised on an integrated product. |
| A48 | NOT_RUN | Not exercised on an integrated product. |
| A49 | IN_PROGRESS | Independent domain evidence only; product/native/integration checks pending. |
| A50 | IN_PROGRESS | Independent domain evidence only; product/native/integration checks pending. |
| A51 | IN_PROGRESS | Independent domain evidence only; product/native/integration checks pending. |
| A52 | IN_PROGRESS | Independent domain evidence only; product/native/integration checks pending. |
| A53 | IN_PROGRESS | Independent domain evidence only; product/native/integration checks pending. |
| A54 | IN_PROGRESS | Independent domain evidence only; product/native/integration checks pending. |

## Evidence index

- [Environment and compiler check](environment.md)
- [Codex field mapping, real test and source decision](codex-integration.md)
- [Native panel, Focus and lifecycle investigation](native-feasibility.md)
- [Performance — not yet run](performance.md)
- [Release — not yet qualified](release.md)
- [Source and development artifact identities](source-manifest.json)

Local ignored logs: `artifacts/preflight/environment.txt`, `core-tests.txt`, `app-build.txt`, `probe-build.txt`, `codex-proxy.txt`, `codex-owned-stdio.txt`, `native-inspect.txt`, `native-smoke.txt`, `test-thread-read.json`. Raw credentials and conversation contents were not written into these logs. Earlier live observations are summarized in the source report with their provenance rather than falsely presented as captured raw files.

## Remaining implementation boundary

Next required engineering evidence is a complete, account-scoped desktop source with durable waiting/completion occurrences and a proven bootstrap boundary. The experimental Swift IPC adapter and vnode read refresh now work for the designated local thread; they do not establish full account/task scope. Continue source investigation before composing the production adapter. Native checks now include user-confirmed pinned fullscreen/Spaces and Focus authorization; see the native report for exact iterations and remaining cases. Audio and production connected status must remain disabled until their dependencies pass.
