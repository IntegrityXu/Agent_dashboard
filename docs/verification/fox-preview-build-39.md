# Red fox preview — 0.2.2 build 39

Verified October 26, 2026 (America/New_York). Release tag: `v0.2.2-preview.39`.

## Changes

- Current source and application resources replace the retired Joker/crown artwork with the red fox avatar, sleeping avatar, head-derived application icon and fox-tail menu bar icon.
- Thirty minutes without observed conversation activity selects the sleeping avatar. Accepted new live patches and inventory changes wake it; fresh running-work evidence keeps it awake. Quota refreshes, identical inventory polls, replayed patches and baseline snapshots do not manufacture activity. The idle timer is in memory and starts anew at application launch.
- Current artwork provenance and MIT scope follow the maintainer's October 26 confirmation that GPT generated the artwork without reference images. Historical artwork records remain separate.
- `scripts/package-app.sh` bundles the five license/policy files before signing. `bash scripts/package-release.sh` builds the universal ZIP, verifies architectures and notices, rejects retired resources, and writes SHA256SUMS.txt.

## Validation

- `./scripts/test-core.sh`: **163 tests passed**, including seven new avatar timing and activity-source tests.
- `bash scripts/test-window-recovery.sh`: **185 native assertions passed** using synthetic data, without Codex monitoring or production preference writes.
- Inspected the application icon and rendered awake, sleeping and compact sleeping cases; the README screenshot uses synthetic fixture data.
- Clean Xcode Release build and ad-hoc signing succeeded. Executable contains **x86_64 and arm64**; bundle metadata is **0.2.2 / 39**, minimum macOS **15.0**.
- ZIP CRC validation passed. Every extracted file matches the packaged application. `codesign --verify --deep --strict` passed on the extracted app.
- Bundled AppIcon.icns and the three runtime SVGs match their current source files. No joker_right.png or crown.png remains anywhere in the application bundle.
- LICENSE, DISCLAIMER.md, PRIVACY.md, THIRD_PARTY_NOTICES.md and SECURITY.md are byte-identical to the source files under `Contents/Resources/Legal/`.

Artifact: `StatusBoard-0.2.2-build39-macOS-universal.zip` (3,852,664 bytes).

SHA-256: `a9c87bb8d3cd05bb801447bbc4a17127c05d79c2541d8e67fdb70b3c026060c8`.

Local generated logs and extraction evidence are under `.build/release-preview-39/`; native renders are under `.build/window-recovery/design-cases/`. These directories are not source dependencies and are not committed.

## Limits

Runtime and native GUI validation were performed on Intel macOS 15.8.1. Universal compilation does not replace a full Apple Silicon runtime check. No clean-machine installation, 30-minute wall-clock soak or new long-term stability claim is made by the deterministic timing tests. The app remains an ad-hoc-signed preview without Developer ID signing or notarization; existing Codex compatibility and feature-coverage limitations still apply.
