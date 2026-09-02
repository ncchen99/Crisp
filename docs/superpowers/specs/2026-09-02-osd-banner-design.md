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

As built (2026-09-02, measured against the native volume HUD on the Dell U4919DW and the built-in display, both over a plain white window so the numbers compare): 290 by 63 points, right edge 12 points in, top 10 points below the menu bar, corner radius 26 with a continuous curve, which follows the native corner within a point on every row of it (a circular 22 runs up to 6 points tight at the top of the corner). Regular glass and a tint both stay light over light content while the native capsule is dark with white text in either appearance, so the banner is glass under a scrim with the content forced to the dark appearance on the hosting view only: on the panel or the glass the dark appearance makes the glass overshoot its tone for 200 ms on every entry. The appearance changes nothing else, in either mode, and the native capsule ignores it too. The glass is not the public clear style. Clear glass blurs its backdrop away (radius 6), where the system HUD barely blurs, so a grid behind the native capsule stays legible: over a grid whose own luminance standard deviation is 46, the native keeps 10 and clear glass 5. Read out of NSGlassEffectView's own render tree, the HUD's look is the private variant 11 (blur 0, refraction on, no face of its own), so the banner asks for it through the private `_variant` behind two guards, the setter has to exist and the major version has to be 26, and falls back to clear glass otherwise. That variant draws its own edge, though, and it is not the native one: a lens band about 20 points wide and a ring 20 levels dark down three of its four sides, which reads as a grey outline on a light backdrop. So the sheet is oversized, 40 points beyond the capsule on every side, and a mask cuts it back to the capsule shape: what shows is the flat middle of the sheet, and the mask carries the corner. The scrim over it is a flat grey (white 0.379, alpha 0.30), fitted to the native tone line, which is linear in the backdrop (out = 0.68 in + 29): the banner reads 28, 116, 188 and 203 on backdrops of black, mid grey, 233 and white to the native's 29, 116, 187 and 202, and 128.5 over the grid to the native's 128.0. Two differences are left. The backdrop comes through sharper than the native's, standard deviation 15.8 over that grid to the native's 10.3, since nothing between clear glass and this variant exists to pick from. And a flat grey desaturates a coloured backdrop a little more than the native, which keeps its colour through a face colour matrix the view will not take from outside. Label 13 point regular (ink-matched against the native label) 16 points in with its cap top 14 points below the capsule top; glyphs 13 point at the same inset; the track 4 points thick, its centre 40.5 points below the top and one point above the glyph centre line, 4 points from each glyph, the unfilled part 7 percent white, with the native's 17 tick dots (2 points, 11 percent white, 6 points below the track centre, 5 points in from each end). The track fills are explicit white: a SwiftUI primary fill renders dim on the glass. The native capsule also carries a bevel that the masked sheet does not draw, a rim one point wide along its edge. It lifts the capsule by about the same amount whatever is behind it (plus 43 levels over a black backdrop, plus 48 over a light one), so the banner adds white at alpha 0.18 through a plus-lighter layer border, which follows the corner radius and the entry and exit resize: 73 over a body of 28 on black to the native's 72 over 29, and 233 over 188 on a 233 backdrop to the native's 235 over 187. Over pure white the native's rim weakens to plus 15 and the banner's does not, the one place the rim runs hot. Setting the `glassBackground` filter parameters directly is a dead end, whatever the variant: assigning them, writing them by key path and swapping in a copy all read back unchanged, even re-applied at 60 Hz, because the view re-applies its own filter set. The variant number is the only handle. Entry, hold and exit are fitted to the system HUD frame by frame at 60 fps, against the tone the screen actually shows: the native capsule takes about half a second to darken along a curve with a slow start while it grows in from 11 points narrower and 2 points shorter on each side and settles down 5.5 points over 0.35 seconds, eased out. One fade carries the whole capsule, tint included: over a grid backdrop the glass reaches its own blur on the same half second, so a faster fade with a separate tint animation brings the blur in too early, which is visible as the banner arriving sharp and then softening. It holds 1 second after the last press, then lifts back, shrinks a little further than it grew from (14 by 3 points a side) over 0.45 seconds along a cubic bezier with control points (0.2, 0.4) and (0.3, 1), and fades on its own group: the native exit falls fast and tails off, and a plain ease-out ends 0.1 seconds too early. The fade in runs 0.55 seconds on a bezier with control points (0.4, 0.05) and (0.2, 0.9), the fade out 0.54 seconds on (0.2, 0.65) and (0.35, 1). Measured on the same white window, the native takes 163 milliseconds to fall from four fifths of its tone to one fifth and 291 to a twentieth, the banner 163 and 297, and through the entry the two track within three hundredths of each other once the system's own 66 millisecond lag before its capsule appears is taken out. A press during the entry lets it finish; a press during the exit replays the window part of the entry from the current opacity, with the tint still up.

## Structure

`Services/OSDBannerService.swift`, `@available(macOS 26.0, *)`, `@MainActor`, a shared singleton:

- `panels: [CGDirectDisplayID: OSDBannerPanel]`, one per screen, created on first use for that screen and never ordered out afterwards. Taking a glass surface off screen replays the materialize bloom on the next order-in (the menu panel note in AppDelegate), so hidden means alpha 0. Every show from hidden plays the entry animation (see As built), which also masks the one-time bloom.
- `show(level:image:on:)`: prune panels whose display is no longer in `NSScreen.screens`, get or create the panel for the screen, update the model, then `reveal(at:)` with the frame recomputed from the screen (resolution changes covered): the entry animation when hidden or fading, a plain move when visible, and the hide timer restarted either way.
- Hide timer: 1 second after the last show, then the 0.45 second shrink with the fade to alpha 0 beside it.
- Key repeat only touches the model and the timer. No allocation per press.
- The panel: borderless, non-activating, `ignoresMouseEvents`, `isOpaque` false, clear background, no AppKit window shadow (the glass edge carries the shape; the edge profile matched the native capsule to within two pixels without one), `animationBehavior` none, `hidesOnDeactivate` false, level 2005, collection behaviour transient, ignores cycle, can join all Spaces, full-screen auxiliary.
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

- Brightness keys with the pointer on the Dell U4919DW: banner at the top right of the Dell, level tracks the key steps, fades 1 second after the last press, repeats while the key repeats.
- Volume and mute keys with a DDC-volume display as the audio output, if one is at hand; otherwise the volume and mute variants are checked with a temporary dev-only call in the brightness path, removed before the PR.
- All-displays mode with the lid open: a banner on each screen at once, including the built-in.
- A screenshot of the Crisp banner next to the native capsule on the same screen, for the look.
- Lint and compile green; `make test` runs in CI (no Xcode on this Mac).

## Rollout

One PR from `brightness-osd-overlay`. Release notes: Crisp draws its own OSD on macOS 26, in the style of the system's, on the display it adjusts. Reply on #76 after the merge, with the note that the reporter's two asks (which display, what level) were already covered and the look is what changed. Update the pending entry in the local CLAUDE.md.
