# Crisp-drawn OSD banner on macOS 26

Status: approved design, pre-implementation.
Date: 2026-09-02
Issue: #76

## Purpose

Crisp shows an on-screen display for every brightness or volume key press it routes to a display, through the private OSDUIHelper XPC service. On macOS 26 that service draws the pre-Tahoe bezel: a 200 by 200 point square at the bottom centre of the screen with a sixteen-chiclet bar. macOS 26 itself draws a compact glass capsule under the menu bar at the top right of the screen, with the device name and a slider. Red-Pumpkin20 asked on #76 (2026-09-01) for the modern look. MonitorControl gave up on this (their discussions 1799 and 1873: the Tahoe banner is unreachable for third parties, and on 26.0 the helper call landed in the new capsule with an empty bar). BetterDisplay draws its own capsule. Verified on this Mac (26.5.1, Dell U4919DW, 2026-09-02): the helper window belongs to OSDUIHelper at level 2005; the native capsule is a Control Center window at the same level, 352 by 152 points including transparent margins, the visible capsule about 280 by 54 points, 20 points in from the right edge and 12 below the menu bar.

Decision (Didrik, 2026-09-02): on macOS 26 and later Crisp draws its own banner in the Tahoe style. macOS 14 and 15 keep the helper call, whose bezel still matches the system there. No setting, no classic-style option; Crisp stays lightweight.

## Scope

- The triggers do not change. The three key paths in BrightnessKeyService (under-cursor brightness, all-displays and selected-displays brightness, DDC volume and mute) keep calling `BrightnessHUDService.show(level:image:on:)`.
- On macOS 26 and later that call draws a Crisp banner on the target screen. Below 26 it runs the existing OSDUIHelper code unchanged.
- No preference, no new user-facing string. The label is `NSScreen.localizedName`, for volume as well: the native capsule names the audio device, and the display is the audio device in that path.
- Not interactive. The native capsule accepts pointer input; nobody asked for that.
- No OSD for brightness changes from other sources (panel sliders, presets, crispctl, auto brightness). Same as today.

## Look

A Liquid Glass capsule, `NSGlassEffectView` regular style, corner radius half the height, 280 by 54 points. Placed on the target screen with its right edge 20 points in from the screen's right edge and its top 12 points below the visible frame's top, so it sits under the menu bar, or 12 points below the screen edge when the menu bar is hidden.

Inside, top to bottom: the display name in a small secondary label, then a level track with a symbol at each end. Brightness: `sun.min.fill` and `sun.max.fill`. Volume: `speaker.fill` and `speaker.wave.3.fill`. Mute: `speaker.slash.fill` on the left, an empty track, no trailing symbol. The track is a thin capsule in the secondary label colour with a primary-colour fill sized by the level. Text and symbols use the primary and secondary label colours so the glass adapts to light and dark on its own. Exact sizes, weights and paddings are tuned live against a screenshot of the native capsule on the same screen.

Window level 2005, the value both OSDUIHelper and Control Center use on 26.5.1, so the banner sits where the system's own does. Collection behaviour joins all Spaces and shows over full-screen apps, like the menu panel.

## Structure

`Services/OSDBannerService.swift`, `@available(macOS 26.0, *)`, `@MainActor`, a shared singleton:

- `panels: [CGDirectDisplayID: OSDBannerPanel]`, one per screen, created on first use for that screen and never ordered out afterwards. Taking a glass surface off screen replays the materialize bloom on the next order-in (the menu panel note in AppDelegate), so hidden means alpha 0. The first show of each panel fades in over about 0.12 seconds to mask the one-time bloom, later shows are instant.
- `show(level:image:on:)`: prune panels whose display is no longer in `NSScreen.screens`, get or create the panel for the screen, recompute its frame from the screen (resolution changes covered), update the model, set alpha 1, restart the hide timer.
- Hide timer: 1.5 seconds after the last show, the same as today's `msecUntilFade`, then a 0.3 second fade to alpha 0.
- Key repeat only touches the model and the timer. No allocation per press.
- The panel: borderless, non-activating, `ignoresMouseEvents`, `isOpaque` false, clear background, no AppKit window shadow (the glass edge carries the shape; a system shadow is tried live and kept only if it matches the native capsule), `animationBehavior` none, `hidesOnDeactivate` false, level 2005, collection behaviour transient, ignores cycle, can join all Spaces, full-screen auxiliary.
- Content: an `NSGlassEffectView` filling the panel, its `contentView` an `NSHostingView` of the banner view.

`Views/OSDBannerView.swift`: SwiftUI, driven by an observable model with title, kind (brightness, volume, mute) and level in 0 to 1 (the service divides the call site's percentage by 100). About 40 lines.

`BrightnessHUDService.show(level:image:on:)`: `if #available(macOS 26.0, *)` forward to the banner service and return, otherwise the existing XPC code. The `OSDImage` enum stays as the shared vocabulary of the call sites.

## Edge cases

- All-displays mode adjusts several screens per press and shows one banner per screen at the same time. Per-screen panels cover it.
- The built-in display shows the Crisp banner in the all-displays and selected modes, since Crisp consumes the key there and macOS draws nothing. In under-cursor mode with the pointer on the built-in, Crisp passes the key through and macOS draws its own capsule; the two never overlap.
- Extra Brightness: the call sites already pass the level as a percentage of the display's extended maximum, so the track shows the position within the extended range, as the chiclets did.
- Screen goes away while a banner is parked: the panel stays at alpha 0 until the next show prunes it.
- A screen without a matching NSScreen never reaches the service; the call sites guard that already.

## Compatibility

- `NSGlassEffectView` exists in the macOS 26 SDK only, and CI builds on that SDK with a macOS 14 deployment target. The service file is gated with `@available(macOS 26.0, *)`, the call with `#available`.
- Both build modes must stay green: `swiftc -swift-version 5` in `make dev` and Swift 6 in Xcode with minimal strict concurrency. Everything in the service is main-actor bound.
- Strict SwiftLint is part of `make check`.

## Testing and verification

No unit test: the only pure logic is the frame arithmetic, two lines. Live verification with `make dev`:

- Brightness keys with the pointer on the Dell U4919DW: banner at the top right of the Dell, level tracks the key steps, fades after 1.5 seconds, repeats while the key repeats.
- Volume and mute keys with a DDC-volume display as the audio output, if one is at hand; otherwise the volume and mute variants are checked with a temporary dev-only call in the brightness path, removed before the PR.
- All-displays mode with the lid open: a banner on each screen at once, including the built-in.
- A screenshot of the Crisp banner next to the native capsule on the same screen, for the look.
- Lint and compile green; `make test` runs in CI (no Xcode on this Mac).

## Rollout

One PR from `brightness-osd-overlay`. Release notes: Crisp draws its own OSD on macOS 26, in the style of the system's, on the display it adjusts. Reply on #76 after the merge, with the note that the reporter's two asks (which display, what level) were already covered and the look is what changed. Update the pending entry in the local CLAUDE.md.
