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

    /// Measured from the native capsule on 26.5.1, at rest: 10 pt in from
    /// the right screen edge, 10 pt below the menu bar, corner radius 20 with
    /// a continuous curve. The 292 x 64 size lives on the view. Read off the
    /// lit columns of both capsules over a banded backdrop: the HUD's run
    /// ends one pixel further right than this one's did at inset 11, and both
    /// runs are the same 292 wide.
    ///
    /// Measure the native capsule at rest, a second after the key press: it
    /// settles down from above over the first half second, and a frame caught
    /// during that settle reads 2 pt narrower, 1 pt shorter and rounder than
    /// the capsule the eye actually sees.
    static let trailingInset: CGFloat = 10
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
    /// the fitting. The amounts the system's own glass variants carry, -26 to
    /// -80, move this backdrop by well under a point.
    ///
    /// Refitted on the tone the edge actually shows, which the displacement
    /// alone missed: over a backdrop of 16 pt bands, how far each column in
    /// from the edge sits off the flat tone the middle of the capsule holds.
    /// The HUD reads 33, 27, 22, 20, 19, 18, 13, 11 and 11 levels off at 2 to
    /// 10 pt in; -110 read 35, 30, 27, 22, 20, 19, 17, 14 and 12, a quarter
    /// strong the whole way in, which is the dark band the eye finds along
    /// the bottom edge over a bright window. This amount reads 32, 27, 21,
    /// 21, 20, 17, 14, 12 and 11: within a level of the HUD at every column.
    static let refractionAmount = -80.0
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

    /// Crisp's own menu bar item, handed over by AppDelegate once it exists.
    /// The system hangs each HUD under the menu bar item that owns it, so the
    /// banner hangs under Crisp's and the two stop landing on top of each
    /// other. Weak: the item outlives the banner, and neither owns the other.
    weak var statusItem: NSStatusItem?

    /// Lights that menu bar item while the banner is up, the way the system
    /// lights the Sound control while its own HUD is up. AppDelegate does the
    /// lighting, because an open panel holds the same highlight.
    var setHighlight: ((Bool) -> Void)?

    /// Takes a level the pointer set on a banner's track: the display, what it
    /// was showing, and 0...1 of the scale that banner shows. AppDelegate
    /// wires this to the same services the keys use.
    var onSlide: ((CGDirectDisplayID, OSDImage, Double) -> Void)?

    private var unlightWork: DispatchWorkItem?

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
        // Re-wired on every show: the display is the panel's own, but what it
        // is showing is not (brightness one press, volume the next).
        panel.model.slide = { [weak self] fraction in self?.onSlide?(displayID, image, fraction) }
        panel.model.dismiss = { [weak panel] in panel?.dismiss() }
        // The frame is recomputed every time: a resolution change moves the
        // screen edge, and the menu bar item moves on its own.
        panel.reveal(at: Self.frame(on: screen, centredOn: anchorMidX(on: screen)))
        light()
    }

    /// Centred on Crisp's menu bar item, under the menu bar (visibleFrame
    /// excludes it), and never closer than `trailingInset` to either side
    /// edge. Measured on the system HUD: the brightness capsule's centre sits
    /// on the Display control's, to half a point, and the volume capsule sits
    /// at the trailing inset because centring it on the Sound control would
    /// take it past the screen edge. With no item to measure, the top right
    /// corner, which is where the banner always sat before.
    static func frame(on screen: NSScreen, centredOn midX: CGFloat?) -> NSRect {
        let width = OSDBannerView.size.width
        let corner = screen.frame.maxX - trailingInset - width
        var x = corner
        if let midX {
            x = min(max(midX - width / 2, screen.frame.minX + trailingInset), corner)
        }
        // The window is the capsule plus the overhang the close badge needs.
        return NSRect(x: x,
                      y: screen.visibleFrame.maxY - topInset - OSDBannerView.size.height,
                      width: width, height: OSDBannerView.size.height)
            .insetBy(dx: -windowMargin, dy: -windowMargin)
    }

    /// Where Crisp's menu bar item sits on `screen`, or nil when there is no
    /// item to hang under. The item is on one screen at a time and the menu
    /// bar carries the same items on all of them, so its offset from the right
    /// edge holds on the others; AppDelegate.positionPanel mirrors the menu
    /// panel the same way. An item the menu bar has no room for keeps a window
    /// away from the bar, which the last guard drops.
    private func anchorMidX(on screen: NSScreen) -> CGFloat? {
        guard let window = statusItem?.button?.window,
              let itemScreen = window.screen,
              window.frame.maxY >= itemScreen.frame.maxY - 1 else { return nil }
        return screen.frame.maxX - (itemScreen.frame.maxX - window.frame.midX)
    }

    /// Lights the menu bar item while the banner holds, and puts it out as the
    /// banner starts to leave, not when it has gone: measured on the system's
    /// own, its item goes dark between 0.85 and 0.95 seconds after the press,
    /// while its capsule is still half there. One timer for every screen, so a
    /// press anywhere pushes the light out again, like the hide timer.
    private func light() {
        unlightWork?.cancel()
        setHighlight?(true)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // A banner the pointer is on holds itself up, and the system's own
            // item stays lit through that, measured 2.25 seconds after the
            // press. The light goes out with the hold that follows the leave.
            guard !self.panels.values.contains(where: { $0.model.hovering }) else { return }
            self.setHighlight?(false)
        }
        unlightWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleDuration, execute: work)
    }

    /// Called by a panel when the pointer arrives or leaves, so the menu bar
    /// item follows the banner it belongs to.
    fileprivate func hoverChanged(_ hovering: Bool) {
        if hovering {
            unlightWork?.cancel()
            setHighlight?(true)
        } else {
            light()
        }
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
        guard let tone = makeToneFilters() else { return nil }
        return makeBackdrop(frame: frame, blur: backdropBlurRadius, tone: tone, refract: true)
    }

    private static func makeBackdrop(frame: NSRect, blur: CGFloat,
                                     tone: [NSObject], refract: Bool) -> CALayer? {
        guard let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type
        else { return nil }
        let backdrop = backdropClass.init()
        backdrop.frame = frame
        // Also private, and the layer works without them, so each is only set
        // where it exists. windowServerAware is what the system's own glass
        // sets on its backdrop layer (dumped from a live NSGlassEffectView):
        // without it the sample is the app's own view of what is behind the
        // window, which goes stale when nothing on screen changes.
        if backdrop.value(forKey: "scale") != nil {
            backdrop.setValue(backdropScale, forKey: "scale")
        }
        if backdrop.value(forKey: "windowServerAware") != nil {
            backdrop.setValue(true, forKey: "windowServerAware")
        }
        var filters: [Any] = []
        if let blurFilter = makeFilter("gaussianBlur") {
            blurFilter.setValue(blur, forKey: "inputRadius")
            // Or the blur pulls in the transparent outside of the capsule and
            // thins its own edge.
            blurFilter.setValue(true, forKey: "inputNormalizeEdges")
            filters.append(blurFilter)
        }
        filters.append(contentsOf: tone)
        if refract, let refraction = makeRefraction(on: backdrop, frame: frame) {
            filters.append(refraction)
        }
        backdrop.filters = filters
        return backdrop
    }

    /// The close badge's own tone line. The system's badge does not sit on the
    /// capsule at all: it samples the desktop the way the capsule does and
    /// lays its own line over it. Measured over flat backdrops of five tones,
    /// its disc reads 187, 203, 230 and 249 where the desktop reads 56, 116,
    /// 183 and 255, which is out = 0.31 in + 170. No white at any alpha over
    /// the capsule can draw that: it takes alpha 0.65 to land on 203 in the
    /// middle and 0.90 to land on 249 at the top, so over a light desktop a
    /// flat badge reads as a grey disc where the system's is nearly clear.
    /// The pair is not that line: the filters do not realise what they are
    /// asked for (0.31 and 0.667 measure as 0.219 and 0.648), so both were
    /// fitted against the system's badge over the same backdrops.
    private static let badgeTone = (multiply: 0.562, add: 0.602)
    /// Heavier than the capsule's: over a checkerboard the system's badge
    /// leaves 3 levels of the backdrop's 59, where the capsule leaves 15.
    private static let badgeBlurRadius: CGFloat = 8

    private static func makeBadgeBackdrop(frame: NSRect) -> CALayer? {
        guard let multiply = makeFilter("multiplyColor"),
              let add = makeFilter("colorAdd") else { return nil }
        multiply.setValue(NSColor(white: badgeTone.multiply, alpha: 1).cgColor, forKey: "inputColor")
        add.setValue(NSColor(white: badgeTone.add, alpha: 1).cgColor, forKey: "inputColor")
        return makeBackdrop(frame: frame, blur: badgeBlurRadius,
                            tone: [multiply, add], refract: false)
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

    /// How far the window reaches past the capsule on every side. The close
    /// badge hangs 2.5 points over the corner and its shadow reaches 30 past
    /// it, and a window cut to the capsule clips both off.
    static let windowMargin: CGFloat = 30

    /// The window is the capsule with that margin around it.
    private static var windowSize: CGSize {
        CGSize(width: OSDBannerView.size.width + 2 * Self.windowMargin,
               height: OSDBannerView.size.height + 2 * Self.windowMargin)
    }

    /// Where the capsule sits inside the window. Views placed here keep their
    /// margins through the entry grow and the exit shrink, since they resize
    /// with the window.
    private static func capsuleRect(in root: NSView) -> NSRect {
        root.bounds.insetBy(dx: Self.windowMargin, dy: Self.windowMargin)
    }

    /// The close badge, centred 6.5 points in from the capsule's top left
    /// corner and 18 across, so it hangs 2.5 points over the corner. Measured
    /// on the system HUD over a flat backdrop.
    private static func badgeRect(in root: NSView) -> NSRect {
        let capsule = capsuleRect(in: root)
        return NSRect(x: capsule.minX + OSDBadgeView.centreInset - OSDBadgeView.size / 2,
                      y: capsule.maxY - OSDBadgeView.centreInset - OSDBadgeView.size / 2,
                      width: OSDBadgeView.size, height: OSDBadgeView.size)
    }

    private func makePanel() -> OSDBannerPanel {
        let p = OSDBannerPanel(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
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

        let root = BannerRootView(frame: NSRect(origin: .zero, size: Self.windowSize))
        root.wantsLayer = true

        // The capsule is what is behind the window, softened and toned down,
        // inside a layer masked to the capsule shape. The content sits above
        // it, so the label, glyphs and track keep their own tone.
        let clip = NSView(frame: Self.capsuleRect(in: root))
        clip.wantsLayer = true
        clip.layer?.cornerRadius = Self.cornerRadius
        clip.layer?.cornerCurve = .continuous
        clip.layer?.masksToBounds = true
        clip.autoresizingMask = [.width, .height]
        if let backdrop = Self.makeBackdrop(frame: clip.bounds) {
            clip.layer?.addSublayer(backdrop)
            p.backdrop = backdrop
        } else {
            let scrim = CALayer()
            scrim.frame = clip.bounds
            scrim.backgroundColor = Self.scrimColor.cgColor
            clip.layer?.addSublayer(scrim)
        }
        root.addSubview(clip)

        let hosting = NSHostingView(rootView: OSDBannerView(model: p.model))
        // Every colour in the banner is explicit, so the appearance only
        // reaches what the system draws itself, which is the held knob's
        // glass. That has to be the light one: the system's own slider knob
        // lifts its backdrop, and dark glass over the capsule's own tone is
        // invisible (measured 102 where the body reads 100). The appearance
        // goes here and not on the panel: the capsule takes its own tone from
        // the grey, and an appearance on the panel would tint that too.
        hosting.appearance = NSAppearance(named: .darkAqua)
        // No intrinsic-size constraints: the content follows the window
        // through the entry grow and the exit shrink.
        hosting.sizingOptions = []
        hosting.frame = Self.capsuleRect(in: root)
        hosting.autoresizingMask = [.width, .height]
        root.addSubview(hosting)

        // Hover is read here and not with SwiftUI's own onHover: onHover wants
        // a key window, and this panel is key only while the pointer is
        // already on it, so a tracking area set to be always active is what
        // sees the pointer arrive. The view takes no
        // clicks (hitTest returns nil), so the track's drag still lands.
        // Three points out, so the badge hanging over the corner is inside it.
        let hover = BannerHoverView(frame: Self.capsuleRect(in: root).insetBy(dx: -3, dy: -3))
        hover.autoresizingMask = [.width, .height]
        hover.onHover = { [weak p] inside in p?.setHovering(inside) }
        root.addSubview(hover)

        // The close badge is drawn here and not in SwiftUI: it samples the
        // desktop the way the system's does, which no fill can, and it hangs
        // over the capsule's corner (see Self.windowMargin).
        let badge = OSDBadgeView(frame: Self.badgeRect(in: root))
        badge.alphaValue = 0
        badge.onClick = { [weak p] in p?.dismiss() }
        if let sample = Self.makeBadgeBackdrop(frame: badge.bounds) {
            badge.disc.addSublayer(sample)
            p.badgeBackdrop = sample
        } else {
            badge.disc.backgroundColor = NSColor.white.withAlphaComponent(0.65).cgColor
        }
        badge.addGlyph()
        root.addSubview(badge)
        p.badge = badge

        // The native capsule carries a rim one point wide along its edge,
        // drawn here over the capsule and its content. Measured at rest it
        // lifts the capsule 74 levels over a black backdrop, 47 over a mid
        // grey and 28 over a light one, which is white blended over, not
        // added: a flat alpha fits all three.
        let bevel = NSView(frame: Self.capsuleRect(in: root))
        bevel.wantsLayer = true
        bevel.layer?.cornerRadius = Self.cornerRadius
        bevel.layer?.cornerCurve = .continuous
        bevel.layer?.borderWidth = 1
        bevel.layer?.borderColor = NSColor.white.withAlphaComponent(0.36).cgColor
        bevel.autoresizingMask = [.width, .height]
        // Under the content and the hover view: a plain NSView takes every
        // click inside its bounds, and this one covers the whole capsule.
        root.addSubview(bevel, positioned: .below, relativeTo: hosting)

        p.contentView = root
        return p
    }
}

/// The window is bigger than the capsule so the badge and its shadow have
/// room (see OSDBannerService.windowMargin), and a banner that is up takes
/// mouse events. This hands back everything outside the capsule, or the
/// margin would swallow clicks on the menu bar above the banner and on the
/// desktop around it.
@available(macOS 26.0, *)
final class BannerRootView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        // The same three points the hover view takes, which is what holds the
        // badge hanging over the capsule's corner.
        let live = bounds.insetBy(dx: OSDBannerService.windowMargin - 3,
                                  dy: OSDBannerService.windowMargin - 3)
        return live.contains(local) ? super.hitTest(point) : nil
    }
}

/// The close badge: a disc that samples the desktop through its own backdrop
/// layer, with the system's xmark over it. AppKit and not SwiftUI, because a
/// SwiftUI fill can only blend with the capsule under it, and the system's
/// badge reads the desktop straight (see OSDBannerService.badgeTone).
@available(macOS 26.0, *)
final class OSDBadgeView: NSView {
    /// Measured on the system HUD: 18 points across, its centre 6.5 points in
    /// from the capsule's top left corner.
    static let size: CGFloat = 18
    static let centreInset: CGFloat = 6.5

    var onClick: (() -> Void)?
    /// The disc itself. It is a sublayer and not this view's own layer because
    /// the shadow below has to fall outside it, and a layer that masks its
    /// content to a circle masks its shadow away with it.
    private(set) var disc = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        disc.frame = bounds
        disc.cornerRadius = frame.width / 2
        disc.masksToBounds = true
        layer?.addSublayer(disc)
        layer?.insertSublayer(makeShadow(), below: disc)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// The shadow the system's badge sits on, which is what makes it an object
    /// over a light desktop rather than a disc that disappears into it. A
    /// layer shadow cannot draw it: the system's reaches more than 20 points
    /// past the disc, and a CALayer shadow at any radius has faded by then.
    /// So it is a radial gradient, its stops read straight off the system's
    /// badge over a white backdrop, where the white drops 33 levels at the
    /// disc's edge, 20 seven points out, 10 eleven points out and is still 3
    /// down 22 points out. Masked to the outside of the disc: the disc is a
    /// backdrop sample and lets anything under it through, which took ten
    /// levels off its own tone.
    private static let shadowReach: CGFloat = 36
    private static let shadowStops: [(CGFloat, CGFloat)] = [
        (0.25, 0.121), (0.278, 0.121), (0.333, 0.081), (0.389, 0.060),
        (0.472, 0.043), (0.556, 0.033), (0.667, 0.023), (0.778, 0.017),
        (0.861, 0.015), (1.0, 0)
    ]

    private func makeShadow() -> CALayer {
        let reach = Self.shadowReach
        let shadow = CAGradientLayer()
        shadow.type = .radial
        shadow.frame = CGRect(x: bounds.midX - reach, y: bounds.midY - reach,
                              width: reach * 2, height: reach * 2)
        shadow.startPoint = CGPoint(x: 0.5, y: 0.5)
        shadow.endPoint = CGPoint(x: 1, y: 1)
        shadow.colors = Self.shadowStops.map { NSColor.black.withAlphaComponent($0.1).cgColor }
        shadow.locations = Self.shadowStops.map { NSNumber(value: Double($0.0)) }
        let hole = CGMutablePath()
        hole.addRect(CGRect(origin: .zero, size: shadow.frame.size))
        hole.addEllipse(in: CGRect(x: reach - bounds.width / 2, y: reach - bounds.height / 2,
                                   width: bounds.width, height: bounds.height))
        let mask = CAShapeLayer()
        mask.frame = CGRect(origin: .zero, size: shadow.frame.size)
        mask.path = hole
        mask.fillRule = .evenOdd
        mask.fillColor = NSColor.black.cgColor
        shadow.mask = mask
        return shadow
    }

    /// The glyph over the disc. Its weight is what fits it: the system's
    /// covers 29 pixels at 1x and its ink adds up to about 1900 levels below
    /// the disc, where 9 point bold covers 29 at 1975 and every lighter weight
    /// leaves the X too thin (8.5 regular covers 19 at 1003). The ink is black
    /// at half, not a flat grey: swept over six backdrops the system's ink is
    /// 90, 93, 100, 112, 119 and 125 where its disc is 178, 185, 199, 224, 238
    /// and 249, which is the same half of the disc every time.
    func addGlyph() {
        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        guard let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let view = NSImageView(image: image)
        view.contentTintColor = NSColor(white: 0, alpha: 0.498)
        // Centred on its ink and not on its image. SF Symbols carry their own
        // bearings: the xmark's ink sits in x 1.000 to 8.375 of a 10 by 10
        // image, a third of a point left of the middle, and the badge's own
        // frame lands on a half point (its centre is 6.5 in from the capsule's
        // corner), which moves it again. Measured on screen at three quarters
        // of a point left of the disc's centre, so it is put back by that.
        view.frame = bounds.offsetBy(dx: 0.75, dy: 0)
        view.imageScaling = .scaleNone
        view.autoresizingMask = [.width, .height]
        addSubview(view)
    }

    /// Round, and only while the badge is there to be clicked.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard alphaValue > 0.5 else { return nil }
        let local = convert(point, from: superview)
        let radius = bounds.width / 2
        return hypot(local.x - bounds.midX, local.y - bounds.midY) <= radius ? self : nil
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// One banner window. Holds its model and the hide timer; OSDBannerService
/// owns placement and content.
@available(macOS 26.0, *)
@MainActor
final class OSDBannerPanel: NSPanel {
    /// Only ever while the pointer is on the capsule, see setHovering.
    override var canBecomeKey: Bool { true }

    let model = OSDBannerModel()
    /// The capsule's backdrop layer, or nil when the private class was
    /// missing and the banner fell back to the flat grey. See keepAlive.
    var backdrop: CALayer?
    /// The close badge and the layer it samples the desktop with.
    var badge: OSDBadgeView?
    var badgeBackdrop: CALayer?
    private var hideWork: DispatchWorkItem?
    private var keepAliveWork: DispatchWorkItem?
    /// Where the banner sits when it is up. Kept so a pointer arriving during
    /// the exit can bring it back to the frame it was leaving.
    private var restFrame: NSRect = .zero
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
        keepAliveWork?.cancel()
        startKeepAlive()
        restFrame = frame
        // A banner on screen is a control: the pointer gets a knob on the
        // track and a close badge, as the system HUD does. It takes clicks
        // only while the pointer is on the capsule, see setHovering.
        ignoresMouseEvents = !model.hovering
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
        scheduleHide()
    }

    /// The hold before the banner leaves, restarted by every press and by the
    /// pointer leaving the capsule.
    private func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.model.hovering else { return }
            self.fadeOut()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + OSDBannerService.visibleDuration, execute: work)
    }

    /// The pointer arriving on the capsule or leaving it. While it is on, the
    /// banner holds: the system's own stays up as long as the pointer is there
    /// and starts its hold again when it leaves, measured at 0.2, 0.6, 1.0 and
    /// 1.45 seconds after the leave. A pointer landing on a banner that is
    /// already leaving brings it back.
    func setHovering(_ hovering: Bool) {
        // A banner that has gone stays gone. Hidden means alpha 0 and the
        // window is still there, so the pointer crossing the corner it used to
        // be in still reaches this, and it must not bring it back.
        if hovering && alphaValue == 0 { return }
        guard model.hovering != hovering else { return }
        model.hovering = hovering
        // The window is wider than the capsule (see windowMargin), and a
        // window takes every click inside it whatever its views say: a view
        // that hands the point back stops the view below it from seeing the
        // click, not the window below the window. So the banner is only
        // clickable while the pointer is on the capsule, and the margin, which
        // covers the menu bar over the banner, never swallows anything. The
        // tracking area that calls this fires whether the window takes clicks
        // or not, so the pointer arriving is always seen.
        ignoresMouseEvents = !hovering
        // AppKit draws a slider in a window that is not key in its inactive
        // state: a grey line and a knob with no glass. The panel is key for
        // exactly as long as the pointer is on the capsule, which is the only
        // way to the real control (see OSDBannerView.track), and it hands the
        // keyboard straight back on the way out. It cannot hold key while the
        // banner is merely up, or every brightness press would take the
        // keyboard away from whatever is in front.
        if hovering {
            makeKey()
        } else if isKeyWindow {
            NSApp.deactivate()
        }
        OSDBannerService.shared.hoverChanged(hovering)
        fadeBadge(to: hovering)
        if hovering {
            hideWork?.cancel()
            if exiting || alphaValue < 1 { reveal(at: restFrame) }
        } else {
            scheduleHide()
        }
    }

    /// The badge fades and only fades, measured on the system HUD over a flat
    /// backdrop at 75 frames a second: 0.29 seconds in on an ease-out that is
    /// only a little faster than a straight line, and 0.35 out, which runs
    /// straight. The knob and the fill are not animated at all.
    private func fadeBadge(to shown: Bool) {
        guard let badge else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = shown ? 0.29 : 0.35
            ctx.timingFunction = shown
                ? CAMediaTimingFunction(controlPoints: 0, 0, 0.58, 1)
                : CAMediaTimingFunction(name: .linear)
            badge.animator().alphaValue = shown ? 1 : 0
        }
    }

    /// The close badge: the banner goes at once, on the same exit.
    func dismiss() {
        setHovering(false)
        hideWork?.cancel()
        fadeOut()
    }

    /// Keeps the backdrop sampling while the banner is up. A layer that
    /// samples what is behind it needs the screen composited, and WindowServer
    /// stops compositing a screen with nothing changing on it: the sample then
    /// has nothing in it and the capsule goes dark, and stays dark until
    /// something on screen moves. EDROverlayManager keeps its own overlay
    /// alive against the same promotion, by re-presenting at 5 fps.
    ///
    /// Holding brightness up at 100 percent is exactly the case that hits it:
    /// the level never moves, so the banner redraws nothing of its own and the
    /// screen behind it is still. An animation the eye cannot see (a
    /// thousandth of the layer's opacity) keeps the layer rendering for as
    /// long as the banner is visible, and is taken off as it goes.
    private static let keepAliveKey = "crispBannerKeepAlive"

    private func startKeepAlive() {
        for layer in [backdrop, badgeBackdrop].compactMap({ $0 })
        where layer.animation(forKey: Self.keepAliveKey) == nil {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.999
            pulse.duration = 0.25
            pulse.autoreverses = true
            pulse.repeatCount = .greatestFiniteMagnitude
            layer.add(pulse, forKey: Self.keepAliveKey)
        }
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
        let work = DispatchWorkItem { [weak self] in
            self?.backdrop?.removeAnimation(forKey: Self.keepAliveKey)
            self?.badgeBackdrop?.removeAnimation(forKey: Self.keepAliveKey)
            // Hidden means alpha 0, not off screen, so the window is still
            // there to take a click nobody meant for it.
            self?.ignoresMouseEvents = true
            self?.model.hovering = false
            self?.badge?.alphaValue = 0
        }
        keepAliveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + OSDBannerService.fadeOutDuration, execute: work)
    }

    /// The hidden frame: `frame` inset and lifted by the native amounts.
    private static func hidden(_ frame: NSRect, inset: CGSize) -> NSRect {
        frame.insetBy(dx: inset.width, dy: inset.height).offsetBy(dx: 0, dy: OSDBannerService.hiddenLift)
    }
}

/// Reads the pointer arriving on the banner and leaving it. SwiftUI's own
/// onHover tracks in the key window, and this panel never becomes key, so the
/// tracking area is set to be always active. It takes no clicks: hitTest
/// returns nil, so the track's drag and the close badge see them instead.
@available(macOS 26.0, *)
final class BannerHoverView: NSView {
    var onHover: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
