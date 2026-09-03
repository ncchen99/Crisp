import AppKit
import SwiftUI

/// Draws Crisp's own on-screen display on macOS 26, in the style of the
/// system's brightness and volume capsule under the menu bar. OSDUIHelper,
/// which BrightnessHUDService still calls on macOS 14 and 15, draws the
/// pre-Tahoe bottom-centre bezel on 26, and the system's own capsule
/// (Control Center's SystemBanner) has no third-party entry point (#76).
///
/// One panel per screen, created on first use and never ordered out: a
/// surface that samples what is behind it replays its materialize bloom when
/// it comes back on screen (see the menu panel notes in AppDelegate), so
/// hidden means alpha 0. Screens that vanish get their panel closed on the
/// next show.
@available(macOS 26.0, *)
@MainActor
final class OSDBannerService {
    static let shared = OSDBannerService()
    private init() {}

    /// Measured from the native capsule on 26.5.1, at rest: 11 pt in from
    /// the right screen edge, 10 pt below the menu bar, corner radius 20 with
    /// a continuous curve. The 292 x 64 size lives on the view.
    ///
    /// Measure the native capsule at rest, a second after the key press: it
    /// settles down from above over the first half second, and a frame caught
    /// during that settle reads 2 pt narrower, 1 pt shorter and rounder than
    /// the capsule the eye actually sees.
    static let trailingInset: CGFloat = 11
    static let topInset: CGFloat = 10
    static let cornerRadius: CGFloat = 20
    /// The capsule's tone, as one grey over the backdrop. The system HUD reads
    /// 0.657 x backdrop + 31 on a flat backdrop, so the grey is mixed to draw
    /// the same line: alpha 0.343 leaves that slope, and white 0.355 under it
    /// puts the offset at 31. Measured back over a black, a mid grey and a
    /// light backdrop the banner lands on 31, 129 and 184, the HUD's own
    /// three. The same line is applied inside the backdrop's own filters (see
    /// makeToneFilters); this layer is what draws it if that layer is missing.
    static let scrimColor = NSColor(white: 0.355, alpha: 0.343)
    /// What the capsule does to the colour behind it, which the grey alone
    /// cannot do. A grey at alpha 0.343 keeps 0.657 of the backdrop's colour
    /// away from grey; the HUD keeps 1.26 of it, so a coloured window behind
    /// the banner stayed noticeably duller than behind the HUD. Measured on
    /// four saturated backdrops the HUD lands on the same brightness line as
    /// ours to a tenth of a level and multiplies what is left of the colour by
    /// 1.26 every time, so the sample is saturated by 1.26 / 0.657 after the
    /// grey. Over a strong green the HUD reads 17, 168, 55 and so does this.
    static let backdropSaturation = 1.26 / (1 - 0.343)
    /// The HUD softens its backdrop, and that is most of what tells the two
    /// apart over a real window. Nothing public blurs the way it does, so the
    /// layer samples its backdrop at reduced resolution, as the HUD does, and
    /// blurs the smaller sample.
    ///
    /// Both numbers are fitted against the HUD's own transfer curve, measured
    /// on a backdrop of dark bars of eight widths under both capsules: what
    /// share of a bar group's 204-level contrast survives at 1, 2, 3, 4, 6, 8
    /// and 12 points wide. The eye reads the wide end of that curve, where a
    /// toolbar icon or a word behind the capsule lives, and the wide end is
    /// what a single blur radius sets. The HUD passes 57 and 69 percent of a
    /// 6 and an 8 point bar; a quarter resolution with this radius passes 60
    /// and 73, and the radius the fine detail alone asked for passed 81 and
    /// 88, which is why icons stayed legible through the banner and not
    /// through the HUD.
    static let backdropScale = 0.5
    static let backdropBlurRadius = 3.2
    /// How far the edge bends its backdrop, and over how many points. Both are
    /// fitted against the HUD's own bend, measured as displacement rather than
    /// by eye: a stripe backdrop of one period behind both capsules, and the
    /// phase of that pattern read column by column in from the edge. The HUD
    /// pulls its backdrop 4.8 pt sideways at the strongest point, 8 pt in from
    /// the edge, and lets go 26 pt in. This pair draws 4.3 pt at the same
    /// place and lets go in the same column, with the HUD's second, weaker
    /// shoulder at 15 pt in as well. The height is not a dial: 16 bends
    /// nothing at all and 30 folds the backdrop over itself, so it stays at
    /// 20, which is what the system's own glass carries, and the amount does
    /// the fitting. Nothing weaker than about -100 bends
    /// anything the eye can find: the amounts the system's own glass variants
    /// carry, -26 to -80, move this backdrop by a point.
    static let refractionAmount = -110.0
    static let refractionHeight = 20.0
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
    /// One fade carries the whole capsule, grey included: a separate, slower
    /// animation on the grey brings the backdrop in ahead of the tone, which
    /// reads as the banner arriving sharp. Every curve was fitted against the
    /// native capsule on the same backdrop, so change them by measuring, not
    /// by taste.
    static let visibleDuration: TimeInterval = 1.0
    static let fadeInDuration: TimeInterval = 0.55
    static let fadeInCurve = CAMediaTimingFunction(controlPoints: 0.4, 0.05, 0.2, 0.9)
    static let growDuration: TimeInterval = 0.35
    static let fadeOutDuration: TimeInterval = 0.54
    static let fadeOutCurve = CAMediaTimingFunction(controlPoints: 0.2, 0.65, 0.35, 1)
    static let exitShrinkDuration: TimeInterval = 0.45
    static let exitShrinkCurve = CAMediaTimingFunction(controlPoints: 0.2, 0.4, 0.3, 1)
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

    /// The layer the capsule blurs its backdrop with. Nothing public blurs
    /// this gently: every NSGlassEffectView material and every
    /// NSVisualEffectView material takes the same 204-level step below 20,
    /// against the HUD's 37, and a Core Image filter over the backdrop cannot
    /// touch it, because the window server composites the backdrop, not this
    /// process. CABackdropLayer is private, so it is asked for by name and
    /// every step of the lookup may fail; without it the banner keeps the
    /// scrim alone, which holds the tone exactly and only leaves the backdrop
    /// sharp.
    private static func makeBackdrop(frame: NSRect) -> CALayer? {
        guard let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type,
              let tone = makeToneFilters() else { return nil }
        let backdrop = backdropClass.init()
        backdrop.frame = frame
        // Also private, and the layer works without it, so it is only set
        // where it exists.
        if backdrop.value(forKey: "scale") != nil {
            backdrop.setValue(backdropScale, forKey: "scale")
        }
        var filters: [Any] = []
        if let blur = makeFilter("gaussianBlur") {
            blur.setValue(backdropBlurRadius, forKey: "inputRadius")
            // Or the blur pulls in the transparent outside of the capsule and
            // thins its own edge.
            blur.setValue(true, forKey: "inputNormalizeEdges")
            filters.append(blur)
        }
        filters.append(contentsOf: tone)
        if let refraction = makeRefraction(on: backdrop, frame: frame) {
            filters.append(refraction)
        }
        backdrop.filters = filters
        return backdrop
    }

    /// The grey and the colour, as filters over the sampled backdrop rather
    /// than as a layer over it. Order matters: the grey's line has to be drawn
    /// first and the colour lifted on what it leaves, because saturating the
    /// backdrop first drives a strong colour past black in one channel and
    /// clips it. Multiply then add is that line, mixed from the same grey the
    /// fallback layer uses.
    private static func makeToneFilters() -> [NSObject]? {
        guard let multiply = makeFilter("multiplyColor"),
              let add = makeFilter("colorAdd"),
              let saturate = makeFilter("colorSaturate") else { return nil }
        let alpha = scrimColor.alphaComponent
        multiply.setValue(NSColor(white: 1 - alpha, alpha: 1).cgColor, forKey: "inputColor")
        add.setValue(NSColor(white: alpha * scrimColor.whiteComponent, alpha: 1).cgColor, forKey: "inputColor")
        saturate.setValue(backdropSaturation, forKey: "inputAmount")
        return [multiply, add, saturate]
    }

    private static func makeFilter(_ name: String) -> NSObject? {
        guard let filterClass = NSClassFromString("CAFilter") as? NSObject.Type else { return nil }
        return filterClass.perform(NSSelectorFromString("filterWithName:"), with: name)?
            .takeUnretainedValue() as? NSObject
    }

    /// Bends the backdrop into the capsule's edge, the way a real edge of
    /// glass would. The HUD does this and it is the last thing that tells the
    /// two apart on a patterned backdrop: behind the HUD a straight line
    /// curves along the inside of the edge, behind a plain masked capsule it
    /// runs straight into a hard cut.
    ///
    /// This is the system's own glass filter. It reads the shape it bends
    /// around from a distance-field layer, which is why it draws nothing on a
    /// bare backdrop layer, so the shape layer goes in as a named sublayer
    /// and the filter is pointed at it. The face is left off: the flat grey
    /// carries the tone, and the filter's own face colour never applied here.
    ///
    /// Every class and key is private. Any of them missing leaves the banner
    /// with the blurred backdrop and no bend, which is where it was before.
    private static func makeRefraction(on backdrop: CALayer, frame: NSRect) -> NSObject? {
        guard let sdfClass = NSClassFromString("CASDFLayer") as? CALayer.Type,
              let elementClass = NSClassFromString("CASDFElementLayer") as? CALayer.Type,
              let effectClass = NSClassFromString("CASDFOutputEffect") as? NSObject.Type,
              let filter = makeFilter("glassBackground") else { return nil }
        let shapeName = "@0"
        let shape = sdfClass.init()
        shape.name = shapeName
        shape.frame = frame
        shape.setValue(effectClass.init(), forKey: "effect")
        let element = elementClass.init()
        element.frame = frame
        element.cornerRadius = cornerRadius
        element.cornerCurve = .continuous
        // The element hangs off a plain layer, as it does in the system's own
        // tree; hung directly off the shape layer it is not picked up.
        let holder = CALayer()
        holder.addSublayer(element)
        shape.addSublayer(holder)
        backdrop.addSublayer(shape)
        filter.setValue(shapeName, forKey: "inputSourceSublayerName")
        // This filter carries a blur of its own, and its default is heavy:
        // left alone it takes the banner to 5.2 of the backdrop's fine
        // structure where the HUD leaves 15.4. The gaussian above it is the
        // one that is fitted, so this one is off.
        filter.setValue(0.0, forKey: "inputBlurRadius")
        filter.setValue(1.0, forKey: "inputRefractionOpacity")
        filter.setValue(refractionAmount, forKey: "inputInnerRefractionAmount")
        filter.setValue(refractionHeight, forKey: "inputInnerRefractionHeight")
        filter.setValue(0.0, forKey: "inputOuterRefractionAmount")
        filter.setValue(0.0, forKey: "inputOuterRefractionHeight")
        filter.setValue(-1.0, forKey: "inputRefractionDistance0")
        filter.setValue(0.0, forKey: "inputRefractionDistance1")
        filter.setValue(0.0, forKey: "inputFaceOpacity")
        return filter
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
        // The masked capsule carries the shape: the edge profile matched the
        // native capsule to within two pixels without a WindowServer shadow.
        p.hasShadow = false
        p.animationBehavior = .none
        p.isReleasedWhenClosed = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces, .fullScreenAuxiliary]
        p.alphaValue = 0

        let root = NSView(frame: NSRect(origin: .zero, size: OSDBannerView.size))
        root.wantsLayer = true

        // The capsule is what is behind the window, softened and toned down,
        // inside a layer masked to the capsule shape. The content sits above
        // it, so the label, glyphs and track keep their own tone.
        let clip = NSView(frame: root.bounds)
        clip.wantsLayer = true
        clip.layer?.cornerRadius = Self.cornerRadius
        clip.layer?.cornerCurve = .continuous
        clip.layer?.masksToBounds = true
        clip.autoresizingMask = [.width, .height]
        if let backdrop = Self.makeBackdrop(frame: clip.bounds) {
            clip.layer?.addSublayer(backdrop)
        } else {
            let scrim = CALayer()
            scrim.frame = clip.bounds
            scrim.backgroundColor = Self.scrimColor.cgColor
            clip.layer?.addSublayer(scrim)
        }
        root.addSubview(clip)

        let hosting = NSHostingView(rootView: OSDBannerView(model: p.model))
        // The capsule is dark in either system appearance, as the HUD's is,
        // so its label, glyphs and track are white in both. The appearance
        // goes here and not on the panel: the capsule takes its own tone from
        // the grey, and a dark appearance on the panel would tint that too.
        hosting.appearance = NSAppearance(named: .darkAqua)
        // No intrinsic-size constraints: the content follows the window
        // through the entry grow and the exit shrink.
        hosting.sizingOptions = []
        hosting.frame = root.bounds
        hosting.autoresizingMask = [.width, .height]
        root.addSubview(hosting)

        // The native capsule carries a rim one point wide along its edge,
        // drawn here over the capsule and its content. Measured at rest it
        // lifts the capsule 74 levels over a black backdrop, 47 over a mid
        // grey and 28 over a light one, which is white blended over, not
        // added: a flat alpha fits all three.
        let bevel = NSView(frame: root.bounds)
        bevel.wantsLayer = true
        bevel.layer?.cornerRadius = Self.cornerRadius
        bevel.layer?.cornerCurve = .continuous
        bevel.layer?.borderWidth = 1
        bevel.layer?.borderColor = NSColor.white.withAlphaComponent(0.36).cgColor
        bevel.autoresizingMask = [.width, .height]
        root.addSubview(bevel)

        p.contentView = root
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
    /// Whether an exit has run since the last reveal. A press lands inside one
    /// often, one hold after the press before it. Nothing clears this when the
    /// exit ends on its own: by then stopping it is a pair of no-ops.
    private var exiting = false

    /// Places the banner at `frame` and brings it to full opacity, restarting
    /// the hide timer. A hidden or fading banner plays the system HUD's entry;
    /// a visible one only moves, so key repeat animates nothing.
    func reveal(at frame: NSRect) {
        hideWork?.cancel()
        if exiting {
            // A second animation on a property does not replace the one in
            // flight: both drive the window, and the exit wins, so the banner
            // blinks out and comes back. Stop it where it is and go up from
            // there. Its own alphaValue is still 1 for the first frames, which
            // is why the flag says this and not the value.
            stopAnimations()
            exiting = false
        }
        if Date() < entryEnds {
            // The grow in flight already lands on `frame`.
        } else if alphaValue < 1 {
            entryEnds = Date().addingTimeInterval(OSDBannerService.fadeInDuration)
            // Only from hidden: caught mid-exit the banner is on screen, and
            // dropping it back to the entry frame is a jump the eye sees.
            if alphaValue == 0 {
                setFrame(Self.hidden(frame, inset: OSDBannerService.entryInset), display: false)
            }
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

    /// Leaves the window where the animations have it and lets them go.
    private func stopAnimations() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            animator().alphaValue = alphaValue
            animator().setFrame(frame, display: false)
        }
    }

    private func fadeOut() {
        exiting = true
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
