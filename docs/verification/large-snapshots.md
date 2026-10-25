# Build 14 — streaming status metadata

The user reported continuous Disconnected after build 12. Read-only diagnosis verified Codex build 21477, account identity and quota, then reproduced a desktop frame rejection: one legitimate conversation snapshot was **8,697,586 bytes**, above the observer's 8 MiB full-frame cap.

A temporary build 13 raised the cap and restored connectivity. The user explicitly rejected that as the solution and requested selective reading. Build 14 replaces the receive/parse path; the temporary cap increase is superseded.

## Source investigation

The inspected Codex 21477 desktop subscription has conversation/host/following parameters, and publishes full conversation snapshots followed by patches. No field selector was found in that subscription path. `thread/read` has `includeTurns`/`maxTurns`, but is a different read path and does not replace the desktop fields used for async input, current requests, read state and stream revisions.

Evidence: the locally inspected `main-JI9qDiXp.js` transport adapter's `sendSnapshot` and `sendFollowingChanged`, plus `src-CsH31EEu.js` subscription methods and read hydration. The IPC transport module `application-network-startup-BG13czUt.js` declares the 256 MiB wire ceiling. This is version-specific private-protocol evidence, not a public compatibility guarantee.

## Receive path

`DesktopSocket` now feeds its bounded 64 KiB receive chunks into `DesktopMetadataDecoder`. The decoder consumes framing and JSON incrementally and constructs only selected `WireValue` metadata. It no longer buffers the entire raw frame or decodes a full conversation object before projection.

- State selection derives from the existing `MetadataRule`: runtime/status, active flags, request IDs, unread state, turn/history linkage, async question IDs/cardinality and item acceptance state.
- Ordinary message text, images, tool inputs/outputs, paths and titles are skipped while receiving. These bytes still travel over the desktop socket; the source does not provide a metadata-only subscription.
- Structured async replies are matched and parsed incrementally inside their JSON text string. Only question IDs and type-validation markers survive; question and answer text are discarded. A small canonical envelope preserves the existing classifier's validation rules.
- Patch paths determine field selection. When a JSON object places `value` before `path`, only the metadata-field union is retained; the existing path-specific projection then applies. Long irrelevant scalar patch values are discarded. Array positions and revisions remain intact, including text-only patches.
- Raw wire lengths are bounded by the inspected protocol ceiling without allocating that amount. Retained metadata has an 8 MiB accounting budget, bounded selected strings/node count/nesting, and no full raw frame buffer. The legacy full-frame decoder retains its original 8 MiB limit and is no longer used by the production socket.

## Verification

- 92 Swift tests pass, including streamed 9 MiB snapshots, two 9 MiB text patch orderings, fragmented headers and Unicode escapes, canonical history, reversed patch property order, malformed data, selected-field bounds, and long async replies preserving exact IDs.
- The synthetic 9 MiB snapshot/patch tests retain less than 4 KiB of metadata accounting and process the following completion patch correctly. This is retained parser data, not a claim about whole-process RSS.
- Universal Release packaging and strict ad-hoc signature verification pass for **0.2.1 build 14**.
- The live app stayed Connected for over 60 seconds after initialization with no subsequent disconnect, showing processing 1 / waiting 0 / Done 0 and quota. An independent 15-second read-only session also ended healthy with four classified live streams.
- Live validation and safe per-frame metadata diagnostics are recorded in `artifacts/app-validation/streaming-metadata-live.jsonl` and `streaming-metadata-probe.txt`; only aggregate counters/field lengths are logged, never conversation content.

Full task coverage and the broader performance/stability qualification remain pending. This change reduces retained/decoded content; it does not reduce bytes sent by Codex or add a server-side field-filter feature.
