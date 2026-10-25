# Liquid glass backgrounds — build 23

Implemented the approved visual direction for both the expanded panel and the 54 pt compact avatar. Their existing dimensions, content, controls, status colors, agent rows and latest Waiting/Done badge logic are unchanged.

Both forms share `BoardGlassSurface`. On macOS 15, a public `NSVisualEffectView` samples the background behind the window; neutral translucent shading, a broad highlight and two thin inset highlights provide glass depth. The backdrop does not accept mouse hits. The existing panel shadow is retained. There are no new animation timers or private rendering APIs.

On macOS 26, the surface uses SwiftUI's native `glassEffect(.clear, in:)` with a neutral contrast underlay. [Apple's clear-glass documentation](https://developer.apple.com/documentation/swiftui/glass/clear) describes the need for a dimming layer. Reduce Transparency uses an opaque system background; the compatibility surface strengthens its underlay for increased contrast.

## Verification

- Executed on Intel macOS 15.8.1, using Xcode 26.3 / macOS 26.2 SDK and deployment target macOS 15.
- `scripts/test-window-recovery.sh`: **70 native assertions passed**. This exercises actual AppKit collapse/expand, overhang clicking, window sizing, detail animation, menus, agent-row removal and latest compact badge selection. [Test log](../../artifacts/app-validation/liquid-glass/native-tests.log).
- Inspected light/dark expanded and compact bitmap fixtures for clipping, content legibility and border alignment: [expanded light](../../artifacts/app-validation/liquid-glass/agents-light.png), [expanded dark](../../artifacts/app-validation/liquid-glass/agents-dark.png), [compact Waiting](../../artifacts/app-validation/liquid-glass/compact-latest-waiting-light.png), [compact Done](../../artifacts/app-validation/liquid-glass/compact-latest-done-light.png), [compact dark](../../artifacts/app-validation/liquid-glass/compact-latest-done-dark.png).
- `scripts/package-app.sh`: universal arm64/x86_64 Release succeeded; packaged bundle version is 23. `codesign --verify --deep --strict` passed.
- The prior 106 core tests remain the latest core-suite result; core logic was not changed or rerun for this material-only update.

## Limits

macOS 15 compatibility glass does not reproduce the dynamic optical refraction of native Liquid Glass. The macOS 26 branch was compiled for both architectures but cannot be runtime-tested on this macOS 15 host. Offscreen bitmap fixtures verify view content and highlights; they do not reproduce WindowServer's live blending with the desktop. The generated concept image is a design reference, not evidence of runtime rendering.
