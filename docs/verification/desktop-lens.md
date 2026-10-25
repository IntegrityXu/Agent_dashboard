# Desktop refraction experiment — build 24

**Retired in build 25 at the user’s request.** The running capture stream was stopped and the app’s Screen Recording grant reset. The application now uses the original frosted material; experiment code is retained only under `Archive/DesktopLens/DesktopLensCheck` and is not linked into the app. The preview launcher was removed. The remaining text records the historical experiment.

The user authorized trying Liquid-TUI's capture/Metal approach and granting
screen-recording permission. This is opt-in with `--liquid-glass-preview`;
ordinary launches retain the build 23 material. Both forms keep the existing
layout, foreground, badges and controls.

## Implementation

`DesktopLens.swift` adapts the ScreenCaptureKit -> IOSurface -> Metal approach
from [Liquid-TUI](https://github.com/Pugbread/Liquid-TUI). Attribution and the MIT
license are in `Archive/DesktopLens/Liquid-TUI`; the license is included in the app bundle.
A rounded-rectangle lens shader refracts the real screen region behind the
surface, excludes Status Board itself, and keeps text and controls out of the
shader. A small RGB offset, specular rim and neutral veil define the glass.
Dark-mode background luminance is limited so the existing light text remains
readable over a bright foreign window.

Capture is cropped to the surface plus a 12 pt margin, capped at 20 fps, with
no audio. Rendering runs on complete capture frames rather than an independent
60 fps animation loop. Collapse/expand replaces and stops the old stream.
The screen region follows window position, dimensions and display scale.
Reduce Transparency bypasses capture. Missing permission shows the existing
background. Normal capture frames are not saved or transmitted.

The explicit `--glass-preview-output` QA option saves only the app window via
SCScreenshotManager. A separate temporary `GlassBackdrop` process supplies a
real colorful test window; it is not embedded wallpaper in the product.
The `--glass-preview-tour` option switches forms once and restores the initial
form and frame. These options are not enabled by the normal launcher.

## Verification

- Universal Release build 24 and local ad-hoc signature verification passed.
- Metal compiled and rendered on this Intel Mac's AMD Radeon Pro 560X.
- `scripts/test-desktop-lens.sh`: six GPU assertions passed, covering corner
  alpha, opaque sampled center, horizontal/vertical mapping, neutral center
  color and specular edge output. Uses a synthetic texture, not screen capture.
- Live logs confirmed completed frames in both 320 pt wide expanded and
  54 x 54 pt compact surfaces, and teardown of the old stream at each switch.
- Final native interaction suite: **70 assertions passed**. An earlier run
  overlapped system-permission interaction and failed its foreground-activation
  assertion; rerunning after permission dialogs closed passed all 70.
- [Native test log](../../artifacts/app-validation/desktop-lens/native-tests.log),
  [GPU test log](../../artifacts/app-validation/desktop-lens/gpu-tests.log).
- Actual window captures: [light expanded](../../artifacts/app-validation/desktop-lens/light/expanded-live.png)
  and [light compact](../../artifacts/app-validation/desktop-lens/light/compact-live.png).
  These are native window screenshots with live GPU-rendered captured pixels,
  not generated concept images. The temporary colored backdrop is a separate
  native window used only for comparison.

The user subsequently requested light glass. Application-only preferences
`AppleInterfaceStyle=Light` and `NSRequiresAquaSystemAppearance=YES` select the
light material and existing dark foreground palette without rebuilding or
changing system appearance.

## Limits and permission identity

This is a custom desktop-lens experiment, not Apple's system Liquid Glass.
Capture requires macOS screen-recording authorization and its visible system
indicator. GPU/battery overhead and multi-display movement need broader testing.
Capture has finite latency and protected content may not appear. This preview
uses a cropped region from one display at a time.

With local ad-hoc signing, rebuilding changes the code hash. macOS retained an
old hash even after toggling its permission switch. Resetting only
`ScreenCapture local.statusboard.app` and regranting permission bound the new
hash correctly. The final binary was kept fixed after that grant. Repeated
builds should not be confused with failures of the rendering approach.

The final running app was restarted with only `--liquid-glass-preview` after
saving its light appearance preference. Automatic touring, diagnostics and
screenshot output were disabled; the temporary backdrop window was closed.
The user can inspect normal expand/collapse and dragging on their own desktop.
The light captures include the real windows present behind the panel at capture
time; they are not a promise of a fixed blue wallpaper or uniform background.
