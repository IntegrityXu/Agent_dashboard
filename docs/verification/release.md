# Release qualification

## Current personal preview — 0.2.1 build 20

`dist/Status Board.app` is a runnable universal Release package, locally ad-hoc signed by `scripts/package-app.sh`. It requires macOS 15 or later and the verified Codex build 21477. The latest build record reports successful Release packaging and strict signature verification; build 20 rebuilds and re-signs the personal preview.

The app includes real partial live counters, quota, native panel interactions, user-initiated login registration and build 4–7 Done/reconnection fixes. Build 10 adds serial completion/wait/error sounds and manual mute, with a packaged-driver playback check. Build 11 has 84 passing tests and a successful user-observed async-question count/sound test; see [async-question verification](async-questions.md). Focus integration remains deferred; see [audio evidence](audio.md). Builds 8–9 retain their inventory/session fixes; see [current status](results.md).

Build 12 adds reliable temporary Show recovery and menu-bar Pin/Unpin. The 84 core tests and 26 native window assertions pass; see [window recovery](window-recovery.md).

Build 14 fixes repeated disconnects by incrementally selecting status metadata from the incoming stream. It supersedes the temporary build 13 cap increase. The core suite has 92 passing tests; see [large snapshot recovery](large-snapshots.md).

Build 15 packages the original dinosaur avatar and adds the taller toolbar and confirmed exit. The native probe passes 33 assertions, including Cancel and confirmed Quit. See [UI verification](avatar-toolbar.md).

Build 16 adds the overhanging avatar with a transparent clickable gutter. The native probe now passes 37 assertions, including clicking above the card border to collapse and clicking the compact avatar to expand.

Earlier [preview validation](usable-preview.md) recorded x86_64 + arm64 packaging and a repaired quit-isolation smoke run: the app and its owned helper exited while the pre-existing Codex helper remained. These checks do not certify every lifecycle scenario on the final installed bundle.

## Remaining release qualification

S10 / V14 / G7 are **IN_PROGRESS**, not a claim that no runnable app exists.

- Formal distribution signing/notarization and a qualified stable installation workflow.
- Actual enabled/disabled logout/login cycles and approval/error behavior at the final install path. Launch at Login registration code is already implemented.
- Final-bundle lifecycle, preference restoration, resource checks and clean-build reproducibility under the original V14 procedure.
- Final artifact identity/checksum/source manifest and environment tied to that qualified release; the historical preflight manifest does not identify build 10.
- Full original acceptance and performance/stability evidence; complete task scope and Focus remain unfinished, and audio needs full real-source acceptance under the original specification.

The current artifact is a personal preview, not a notarized or fully qualified original-specification release. No system login setting, saved mute preference, Focus setting, signing identity or profile was changed. The local preview package is updated.

Earlier scaffold-only release statements are preserved in the [historical checkpoint](results-pre-preview.md). Build 4, 5 and 6 reports remain historical evidence for their individual fixes, superseded by build 10 as the audio package baseline; build 11 adds the async-question correction.

Build 17 adds the Codex-row divider and blue/green processing/Done labels. Release packaging, signature verification, light/dark rendering and live connectivity were checked; see [UI evidence](avatar-toolbar.md#build-17--divider-and-status-label-colors).

Build 19 enables the details chevron while retaining Connected/Pinned. Release/signature checks, 45 native interaction assertions and light/dark visual checks pass; see [details disclosure](avatar-toolbar.md#build-19--details-disclosure).

Build 20 adds smooth details disclosure with synchronized native height/content and rapid reversal. The native probe passes 53 assertions; see [animation verification](avatar-toolbar.md#build-20--smooth-details-animation).
