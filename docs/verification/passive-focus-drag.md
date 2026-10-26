# Continuous header dragging and passive focus — build 38

Verified October 24, 2026 (America/New_York).

## Behavior

The header now has one continuous drag surface covering the toolbar, Codex row, surrounding margins and divider gap. Settings, Pin, power, the disclosure button and an open settings menu are excluded using their rendered geometry. The avatar retains click-to-expand/collapse and its movement threshold.

BoardPanel resolves each new drag press against the current native view bounds, including double/triple clicks, and keeps that target through movement and release. This avoids AppKit reusing a previous hosted click target. Native visible rectangles can exceed an unclipped view's own bounds; drag routing explicitly intersects both. Repeated clicks on ordinary controls are delivered as independent single-click actions.

Normal mouse interaction, dragging, showing the panel, expanding/collapsing, pinning and mouse settings do not make the panel key or activate Status Board. A delayed activation notification for the application already in front does not count as switching applications. Outside clicks and actual app switches still end temporary raising.

The menu-bar **Keyboard Settings…** entry and the Settings accessibility action **Use keyboard** explicitly enable keyboard interaction. Escape or completing a setting releases it. Info, Quit and login-error sheets temporarily acquire keyboard focus and restore the previous application/window on dismissal, unless the user has switched elsewhere. Return in Quit still chooses Cancel.

## Verification

- **183 native assertions passed** against the production app sources. Added coverage includes the original header dead zones, repeated-click retargeting, consecutive movement events during redraw, 20 compact/expanded drag cycles, button exclusions and first-click response, caret and responder preservation, actual continued text entry, marked-text preservation, keyboard Settings acquisition/release, Info focus restoration, another application's foreground focus, and actual Return-to-Cancel dispatch. Existing layout, pointer, animation, settings, help, Info and Quit checks also pass.
- **156 Swift package tests passed**.
- Release build succeeded as a universal x86_64/arm64 binary. Strict deep signature verification passed; bundle version is **38**.
- Inspected rendered light/dark panels; visual layout is preserved.

The native harness uses its own preferences domain and no Codex monitoring. It posts controlled native mouse/key events and uses a real NSTextField field editor for typing checks. It does not type into the user's Codex conversation. Physical trackpad gestures, all input methods, Spaces and multiple displays are not exhaustively covered by these tests.

Logs: `.build/focus-drag/native-final.log`, `.build/focus-drag/core.log`, `.build/focus-drag/package.log`.

## GitHub preview packaging — October 26, 2026

Prepared `v0.2.1-preview.38` from the current build 38 sources on Intel macOS
15.8.1 with Xcode 26.3. The application remains ad-hoc signed and has no
Developer ID signature or Apple notarization.

- 156 Swift package tests passed in the normal local environment. The initial
  sandboxed test process exited before completion; the successful run used the
  same test sources outside the filesystem sandbox.
- 185 native assertions passed. The initial native runs exposed obsolete hardcoded
  Settings/Pin coordinates after their layout order changed. The harness now
  clicks each control's rendered frame and asserts those frames are nonempty;
  production application code was not changed for this test correction.
- Release build and strict deep signature verification passed for both the
  packaged app and the app extracted from the ZIP. The executable contains
  `x86_64` and `arm64`; the bundle declares macOS 15.0 as its minimum OS.
- ZIP CRC validation passed, and every archived file matches the rebuilt app
  byte-for-byte. Only the application bundle is included.

Artifact: `StatusBoard-0.2.1-build38-macOS-universal.zip`.
SHA-256: `07113fbc09d51758c8f444fc76751cc9f7e15d384a86842e2bb8328f2705dd55`.
The release also includes `SHA256SUMS.txt` for download verification.

Logs: `.build/release-preview/package.log`, `.build/release-preview/core.log`,
and `.build/release-preview/native.log`. Apple Silicon runtime testing and a
clean-machine Gatekeeper installation check remain unverified.
