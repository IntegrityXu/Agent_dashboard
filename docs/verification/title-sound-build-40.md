# Chat titles and completion sound — 0.2.3 build 40

Verified October 27, 2026 (America/New_York). Release tag: `v0.2.3-preview.40`.

## Changes

- Processing root rows display the account-scoped local conversation's `name`, matching the Codex sidebar. The legacy `title` field can contain the first user prompt and is never selected or used as a fallback.
- Missing or blank names fall back to `Chat ·` and the last six thread-ID characters. A schema without `name` still supports inventory and counts. Refreshing the inventory updates renamed chats and removes names outside the tracked scope.
- Child agent rows retain their short names and status suffixes, with indentation. Their help text includes the parent chat title and full agent path. Existing root-turn lifecycle, count and audio isolation remain unchanged.
- Completion uses the selected 650 ms wooden double tap. The generation script reproduces the exact audition bytes; waiting and failed sounds are unchanged.
- Privacy documentation now covers in-memory conversation display names and their exclusion from ordinary diagnostic logs.

## Validation

- `scripts/test-core.sh --no-parallel`: **165 tests passed**. Coverage includes old schemas, account/archive/child exclusion, legacy-title rejection, rename refresh, removed-chat cleanup, child associations and audio decoding.
- Native window probe: **185 assertions passed**, including title rows, bounded scrolling, completion removal and window sizing. The first release-check attempt was interrupted at its foreground-activation assertion while browser work ran concurrently; the isolated rerun passed. Synthetic light/dark and long-title renders were inspected during implementation.
- Live local verification confirmed the displayed chat name matches Codex, and a short child-agent run appears beneath it with running/completed states. This is a sample check, not an account-wide coverage guarantee.
- Universal Release packaging succeeded with **arm64 and x86_64**, version **0.2.3 / 40**, minimum macOS **15.0**.
- ZIP CRC verification and extracted-app `codesign --verify --deep --strict` passed. Every extracted file matches its packaged counterpart; bundled legal documents match their sources.
- Packaged completion sound is byte-identical to the selected 650 ms audition. Waiting and failed assets are byte-identical to the preceding source revision.

Artifact: `StatusBoard-0.2.3-build40-macOS-universal.zip` (3,861,686 bytes).

SHA-256: `4f91451926dcb2c117f311231c8860dd00d7c9abf676a595ac30b27db67a6f5f`.

Local generated evidence is under `.build/release-preview-40/`, `.build/window-recovery/`, and the release-check logs in the temporary directory. Audition experiments and private live previews are not published.

## Limits

The application remains an ad-hoc-signed preview without Developer ID signing or notarization. Runtime/native checks were performed on Intel macOS; universal compilation does not replace full Apple Silicon runtime acceptance. Existing local-source coverage, ordinary Chat integration, Focus and automatic-update limitations remain. Agent rows represent task relationships, not an operating-system process tree.
