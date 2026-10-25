# Avatar drag and count cursor — build 37

Verified October 24, 2026 (America/New_York).

## Changes, in requested order

1. **Avatar drag and subsequent drag recovery.** The expanded avatar was a plain SwiftUI button, with no drag handler. Compact/avatar-strip dragging separately drained mouse events in a blocking `nextEvent` loop before handing control to `performDrag`. The two interaction paths were inconsistent, and queue consumption made mouse-up completion fragile. Both avatars and both drag strips now use normal AppKit `mouseDown`, `mouseDragged`, and `mouseUp` dispatch. A four-point movement threshold distinguishes clicks from drags; screen coordinates keep movement stable as the window moves. Mouse-up, cancellation, detachment, and a fresh mouse-down clear gesture state. A drag never invokes the collapse/expand click action. Accessibility names/actions and Space/Return operation remain available.
2. **Avatar hover hints.** Removed the expanded “Collapse Status Board” help and compact avatar help. Other hints retain their existing delay. Accessibility labels are retained independently.
3. **Count hand cursor.** Replaced the ineffective SwiftUI-only `pointerStyle(.link)` with native cursor rectangles covering each complete count cell. Pass-through geometry views do not consume clicks. The root `BoardHostingView` manages cursor tracking, including inactive-window tracking and layout refresh; `BoardPanel` applies the cursor after hosted event dispatch. Leaving the region restores the arrow, with no global cursor push/pop stack. Folded/animating details and the settings menu disable these regions. Layout refresh checks that the pointer's topmost window is the panel before setting its cursor.

## Verification

- First-step native run: **111 assertions passed**, including long holds followed by expanded/compact avatar drags, immediate consecutive drags in both other strips, cancellation, no accidental toggle, and click recovery.
- Final native run: **119 assertions passed**. Additional checks move the pointer over each count cell, assert `NSCursor.current` is the pointing hand, assert leaving restores the arrow, verify complete cell geometry and pass-through hit testing, and invoke all three existing count-button actions. Existing panel reveal, pin, details animation, settings, Info, help timing, agent layout and Quit checks also pass.
- **156 Swift package tests passed**, including side chat and idle SQLite regressions.
- Universal Release build and signature verification passed. The native test uses a separate preferences domain and does not start Codex monitoring.

Evidence: `.build/interaction-validation/step1-native.log`, `final-native.log`, `core.log`, and `package.log`. Earlier cursor attempts failed actual cursor checks and were replaced before release.
