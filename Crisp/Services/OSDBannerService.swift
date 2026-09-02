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

    /// Measured from the native capsule on 26.5.1: 20 pt in from the right
    /// screen edge, 12 pt below the menu bar. The 280 x 54 size lives on the view.
    static let trailingInset: CGFloat = 20
    static let topInset: CGFloat = 12
    /// The window level OSDUIHelper and Control Center draw their capsule at.
    static let windowLevel = NSWindow.Level(rawValue: 2005)
    /// Same hold as the msecUntilFade BrightnessHUDService passes the helper.
    static let visibleDuration: TimeInterval = 1.5
    static let fadeDuration: TimeInterval = 0.3

    private var panels: [CGDirectDisplayID: OSDBannerPanel] = [:]

    /// Shows (or refreshes) the banner on `screen`. `level` is 0...100 as the
    /// key paths pass it, a percentage of the display's extended maximum.
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
        // Recomputed every time: a resolution change moves the top-right corner.
        panel.setFrame(Self.frame(on: screen), display: false)
        panel.model.title = screen.localizedName
        panel.model.image = image
        panel.model.level = max(0, min(1, level / 100))
        panel.reveal()
    }

    /// Top-right of the screen, under the menu bar (visibleFrame excludes it),
    /// or under the screen edge when the menu bar is hidden.
    static func frame(on screen: NSScreen) -> NSRect {
        NSRect(x: screen.frame.maxX - trailingInset - OSDBannerView.size.width,
               y: screen.visibleFrame.maxY - topInset - OSDBannerView.size.height,
               width: OSDBannerView.size.width, height: OSDBannerView.size.height)
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
        p.level = Self.windowLevel
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isMovable = false
        p.isOpaque = false
        p.backgroundColor = .clear
        // The glass edge carries the shape; the WindowServer shadow is tried
        // live against the native capsule and kept only if it matches.
        p.hasShadow = false
        p.animationBehavior = .none
        p.isReleasedWhenClosed = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces, .fullScreenAuxiliary]
        p.alphaValue = 0

        let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: OSDBannerView.size))
        glass.cornerRadius = OSDBannerView.size.height / 2
        let hosting = NSHostingView(rootView: OSDBannerView(model: p.model))
        hosting.frame = glass.bounds
        hosting.autoresizingMask = [.width, .height]
        glass.contentView = hosting
        p.contentView = glass
        return p
    }
}

/// One banner window. Holds its model and the hide timer; OSDBannerService
/// owns placement and content.
@available(macOS 26.0, *)
final class OSDBannerPanel: NSPanel {
    let model = OSDBannerModel()
    private var hideWork: DispatchWorkItem?
    private var hasShownOnce = false

    /// Brings the banner to alpha 1 and restarts the hide timer. Key repeat
    /// lands here many times a second: no allocation beyond the work item.
    func reveal() {
        hideWork?.cancel()
        // First show only: a short fade masks the glass materialize bloom, the
        // way the menu panel's first open does. Later shows are instant and
        // replace any in-flight fade-out.
        let duration: TimeInterval = hasShownOnce ? 0 : 0.12
        hasShownOnce = true
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            animator().alphaValue = 1
        }
        let work = DispatchWorkItem { [weak self] in self?.fadeOut() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + OSDBannerService.visibleDuration, execute: work)
    }

    private func fadeOut() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = OSDBannerService.fadeDuration
            animator().alphaValue = 0
        }
    }
}
