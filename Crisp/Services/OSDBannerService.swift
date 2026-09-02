import AppKit
import SwiftUI

/// Draws Crisp's own on-screen display on macOS 26, in the style of the
/// system's brightness and volume capsule under the menu bar. OSDUIHelper,
/// which BrightnessHUDService still calls on macOS 14 and 15, draws the
/// pre-Tahoe bottom-centre bezel on 26, and the system's own capsule
/// (Control Center's SystemBanner) has no third-party entry point (#76).
///
/// One panel per screen, created on first use and never ordered out: taking
/// a Liquid Glass surface off screen replays its materialize bloom on the
/// next order-in (see the menu panel notes in AppDelegate), so hidden means
/// alpha 0. Screens that vanish get their panel closed on the next show.
@available(macOS 26.0, *)
@MainActor
final class OSDBannerService {
    static let shared = OSDBannerService()
    private init() {}

    /// Measured from the native capsule on 26.5.1: 12 pt in from the right
    /// screen edge, 10 pt below the menu bar, corner radius 26 with a
    /// continuous curve. The 290 x 63 size lives on the view.
    static let trailingInset: CGFloat = 12
    static let topInset: CGFloat = 10
    static let cornerRadius: CGFloat = 26
    /// How far the glass sheet overhangs the capsule on every side, so its
    /// own edge treatment falls outside the mask. Wider than the lens band.
    static let glassOverhang: CGFloat = 40
    /// The window level OSDUIHelper and Control Center draw their capsule at.
    static let windowLevel = NSWindow.Level(rawValue: 2005)
    /// Entry, hold and exit fitted to the system HUD, measured frame by
    /// frame on 26.5.1 as the tone the screen actually shows. The capsule
    /// fades in over 0.55 s on a curve with a slow start, while it grows in
    /// from 11 pt narrower and 2 pt shorter on each side and settles down
    /// 5.5 pt over 0.35 s, easing out. It holds 1 s after the last press,
    /// then lifts back and shrinks a little further than it grew from (14 by
    /// 3 pt a side) over 0.45 s, and fades on its own curve, which falls fast
    /// and tails off: the system's takes 163 ms from four fifths of its tone
    /// to one fifth and 291 ms to a twentieth, and this one 163 and 297.
    ///
    /// One fade carries the whole capsule, tint included: the glass reaches
    /// its own blur on the same half second, so a faster fade with a separate
    /// tint animation brings the blur in too early. Every curve was fitted
    /// against the native capsule on the same backdrop, so change them by
    /// measuring, not by taste.
    static let visibleDuration: TimeInterval = 1.0
    static let fadeInDuration: TimeInterval = 0.55
    static let fadeInCurve = CAMediaTimingFunction(controlPoints: 0.4, 0.05, 0.2, 0.9)
    static let growDuration: TimeInterval = 0.35
    static let fadeOutDuration: TimeInterval = 0.54
    static let fadeOutCurve = CAMediaTimingFunction(controlPoints: 0.2, 0.65, 0.35, 1)
    static let exitShrinkDuration: TimeInterval = 0.45
    static let exitShrinkCurve = CAMediaTimingFunction(controlPoints: 0.2, 0.4, 0.3, 1)
    /// The glass the system HUD draws with: no blur, no face of its own. See
    /// `applyHUDGlassVariant(to:)`.
    static let hudGlassVariant = 11
    static let entryInset = CGSize(width: 11, height: 2)
    static let exitInset = CGSize(width: 14, height: 3)
    static let hiddenLift: CGFloat = 5.5

    private var panels: [CGDirectDisplayID: OSDBannerPanel] = [:]

    /// Shows (or refreshes) the banner on `screen`. `level` is 0...100 as the
    /// key paths pass it: for brightness a percentage of the display's extended
    /// maximum, for volume the DDC volume itself.
    func show(level: Double, image: OSDImage, on screen: NSScreen) {
        guard let displayID = Self.displayID(of: screen) else { return }
        prunePanels()
        let panel: OSDBannerPanel
        if let existing = panels[displayID] {
            panel = existing
        } else {
            panel = makePanel()
            panels[displayID] = panel
        }
        panel.model.title = screen.localizedName
        panel.model.image = image
        panel.model.level = max(0, min(1, level / 100))
        // The frame is recomputed every time: a resolution change moves the
        // top-right corner.
        panel.reveal(at: Self.frame(on: screen))
    }

    /// Top-right of the screen, under the menu bar (visibleFrame excludes it),
    /// or under the screen edge when the menu bar is hidden.
    static func frame(on screen: NSScreen) -> NSRect {
        NSRect(x: screen.frame.maxX - trailingInset - OSDBannerView.size.width,
               y: screen.visibleFrame.maxY - topInset - OSDBannerView.size.height,
               width: OSDBannerView.size.width, height: OSDBannerView.size.height)
    }

    /// Switches `glass` to the glass the system HUD draws with. Private, so
    /// it is guarded twice: the setter has to exist, and the variant numbers
    /// are only verified on macOS 26, so a later major keeps the public clear
    /// glass rather than take an unseen look. Either fallback is the banner
    /// with a blurrier backdrop, never a crash.
    private static func applyHUDGlassVariant(to glass: NSGlassEffectView) {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26,
              glass.responds(to: NSSelectorFromString("set_variant:")) else { return }
        glass.setValue(hudGlassVariant, forKey: "_variant")
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private func prunePanels() {
        let live = Set(NSScreen.screens.compactMap(Self.displayID(of:)))
        for (id, panel) in panels where !live.contains(id) {
            panel.close()
            panels[id] = nil
        }
    }

    private func makePanel() -> OSDBannerPanel {
        let p = OSDBannerPanel(
            contentRect: NSRect(origin: .zero, size: OSDBannerView.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Set the level explicitly and never isFloatingPanel: that setter
        // silently resets the level to floating (3), under the menu bar.
        p.level = Self.windowLevel
        p.hidesOnDeactivate = false
        p.isMovable = false
        p.isOpaque = false
        p.backgroundColor = .clear
        // The glass edge carries the shape: the edge profile matched the
        // native capsule to within two pixels without a WindowServer shadow.
        p.hasShadow = false
        p.animationBehavior = .none
        p.isReleasedWhenClosed = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces, .fullScreenAuxiliary]
        p.alphaValue = 0

        // An oversized glass sheet, masked down to the capsule. The glass
        // bends its backdrop into a lens band along its own edge, about 20 pt
        // wide, and darkens a ring inside three of its sides; both land
        // outside the mask when the sheet overhangs, so what shows is the flat
        // middle of it. The mask carries the shape instead, at the corner the
        // native capsule has (radius 26, continuous: measured row by row
        // against it, a circular 22 runs up to 6 pt tight at the top of the
        // corner).
        let clip = NSView(frame: NSRect(origin: .zero, size: OSDBannerView.size))
        clip.wantsLayer = true
        clip.layer?.cornerRadius = Self.cornerRadius
        clip.layer?.cornerCurve = .continuous
        clip.layer?.masksToBounds = true

        let glass = NSGlassEffectView(frame: clip.bounds.insetBy(dx: -Self.glassOverhang, dy: -Self.glassOverhang))
        glass.cornerRadius = Self.cornerRadius + Self.glassOverhang
        // The system capsule is dark glass with white content in either
        // appearance. Regular glass and a tint both stay light over light
        // content, so: glass under a scrim, with the content forced dark.
        glass.style = .clear
        // The system HUD's glass is not the public clear style. Clear glass
        // blurs its backdrop away (radius 6); the HUD's barely blurs, so the
        // backdrop stays legible through it. Measured as the standard
        // deviation of luminance in a patch of the capsule over a grid
        // backdrop, where the backdrop itself is 46: the HUD keeps 10, clear
        // glass 5, this variant 15.
        Self.applyHUDGlassVariant(to: glass)
        glass.autoresizingMask = [.width, .height]
        clip.addSubview(glass)

        // The scrim carries the capsule's tint. One flat overlay puts the
        // banner on the native tone line, which is linear in the backdrop
        // (out = 0.68 in + 29, measured over black, mid grey and white).
        let scrim = NSView(frame: clip.bounds)
        scrim.wantsLayer = true
        scrim.layer?.backgroundColor = NSColor(white: 0.379, alpha: 0.30).cgColor
        scrim.autoresizingMask = [.width, .height]
        clip.addSubview(scrim)

        // The native capsule carries a bevel that the masked sheet does not
        // draw: a rim one point wide along its edge that lifts it about 45
        // levels, the same lift over a black backdrop as over a white one, so
        // it is added rather than blended over.
        let bevel = NSView(frame: clip.bounds)
        bevel.wantsLayer = true
        bevel.layer?.cornerRadius = Self.cornerRadius
        bevel.layer?.cornerCurve = .continuous
        bevel.layer?.borderWidth = 1
        bevel.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        bevel.layer?.compositingFilter = "plusL"
        bevel.autoresizingMask = [.width, .height]
        clip.addSubview(bevel)

        let hosting = NSHostingView(rootView: OSDBannerView(model: p.model))
        // Dark content only: the dark appearance on the panel or the glass
        // makes the glass overshoot its tone for a moment on every entry.
        hosting.appearance = NSAppearance(named: .darkAqua)
        // No intrinsic-size constraints: the content follows the window
        // through the entry grow and the exit shrink.
        hosting.sizingOptions = []
        hosting.frame = clip.bounds
        hosting.autoresizingMask = [.width, .height]
        clip.addSubview(hosting)
        p.contentView = clip
        return p
    }
}

/// One banner window. Holds its model and the hide timer; OSDBannerService
/// owns placement and content.
@available(macOS 26.0, *)
@MainActor
final class OSDBannerPanel: NSPanel {
    let model = OSDBannerModel()
    private var hideWork: DispatchWorkItem?
    /// When the running entry ends. `alphaValue` reads the interpolated value
    /// during a window animation, so a second press inside the entry would
    /// otherwise restart it from the shrunk frame.
    private var entryEnds = Date.distantPast

    /// Places the banner at `frame` and brings it to full opacity, restarting
    /// the hide timer. A hidden or fading banner plays the system HUD's entry;
    /// a visible one only moves, so key repeat animates nothing.
    func reveal(at frame: NSRect) {
        hideWork?.cancel()
        if Date() < entryEnds {
            // The grow in flight already lands on `frame`.
        } else if alphaValue < 1 {
            entryEnds = Date().addingTimeInterval(OSDBannerService.fadeInDuration)
            setFrame(Self.hidden(frame, inset: OSDBannerService.entryInset), display: false)
            orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = OSDBannerService.growDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().setFrame(frame, display: true)
            }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = OSDBannerService.fadeInDuration
                ctx.timingFunction = OSDBannerService.fadeInCurve
                animator().alphaValue = 1
            }
        } else {
            setFrame(frame, display: false)
        }
        let work = DispatchWorkItem { [weak self] in self?.fadeOut() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + OSDBannerService.visibleDuration, execute: work)
    }

    private func fadeOut() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = OSDBannerService.fadeOutDuration
            ctx.timingFunction = OSDBannerService.fadeOutCurve
            animator().alphaValue = 0
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = OSDBannerService.exitShrinkDuration
            ctx.timingFunction = OSDBannerService.exitShrinkCurve
            animator().setFrame(Self.hidden(frame, inset: OSDBannerService.exitInset), display: true)
        }
    }

    /// The hidden frame: `frame` inset and lifted by the native amounts.
    private static func hidden(_ frame: NSRect, inset: CGSize) -> NSRect {
        frame.insetBy(dx: inset.width, dy: inset.height).offsetBy(dx: 0, dy: OSDBannerService.hiddenLift)
    }
}
