import SwiftUI

/// State behind one OSD banner: the display name, which glyph pair to show,
/// and the level as 0...1. Mutated by OSDBannerService on every key press;
/// the panel's hosting view redraws from it.
@available(macOS 26.0, *)
@MainActor
final class OSDBannerModel: ObservableObject {
    @Published var title = ""
    @Published var image: OSDImage = .brightness
    @Published var level = 0.0
    /// Whether the pointer is on the capsule. The system HUD grows a knob and
    /// a close badge then, and holds itself up until the pointer leaves.
    @Published var hovering = false
    /// Takes a level the pointer set on the track, 0...1 of the same scale the
    /// banner shows. Set by OSDBannerService for the display in question.
    var slide: ((Double) -> Void)?
    /// Takes the close badge's click.
    var dismiss: (() -> Void)?
}

/// The banner OSDBannerService draws on macOS 26: the display name over a
/// level track with a symbol at each end, in the style of the system's own
/// brightness and volume capsule under the menu bar. Sizes and paddings are
/// tuned against a screenshot of the native capsule on the same screen.
@available(macOS 26.0, *)
struct OSDBannerView: View {
    /// Visible capsule size, measured from the native HUD on 26.5.1 once it
    /// has settled (see OSDBannerService.cornerRadius).
    static let size = CGSize(width: 292, height: 64)

    @ObservedObject var model: OSDBannerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(model.title)
                // Smaller than the 13 pt it used to be, which is what read as
                // slightly off next to the HUD. Fitted at 2x, where a point is
                // two pixels: the same label drawn at 13, 12.5 and 12 next to
                // the HUD's own, matched to it by sliding one profile over the
                // other, puts the HUD at 12.33, 12.22 and 12.18, and its
                // ascenders (18.5 px against 19.7, 18.9 and 18.1) agree. The
                // glyphs below stay at 13.
                .font(.system(size: 12.25))
                // Explicit white, not .primary: the label colour is white at
                // 85 percent, which reads thinner and duller than the HUD's
                // label (peak 243 against its 251 over the same body).
                .foregroundStyle(.white)
                .lineLimit(1)
                // The row the smaller label costs is given back here, so the
                // track and the glyphs stay on the HUD's rows: the line box at
                // 13 pt is 16 pt tall, and this block's height is what places
                // everything under it.
                .frame(height: 16)
                // A quarter point down, which puts the baseline where the
                // HUD's sits: 22.75 pt under the top of the capsule, measured
                // at 2x on both.
                .offset(y: 0.25)
            HStack(spacing: 4) {
                Image(systemName: leadingSymbol)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                track
                Image(systemName: trailingSymbol)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    // Mute keeps the slot so the track does not grow 27 pt.
                    .opacity(model.image == .mute ? 0 : 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// How far the tick dots' centres sit in from each end of the track.
    /// Measured on the system HUD at 2x: its track runs 450 px, its seventeen
    /// dots 74.5 to 505.5 from the same origin, so 9 px in at both ends.
    private static let tickInset: CGFloat = 4.5

    /// The knob the pointer gets. Measured on the system HUD at four levels:
    /// 16 points across and 14 tall, its centre travelling between the track's
    /// ends inset by half its width, with the fill running to its trailing
    /// edge. At the top of the range its centre stops 8 points short of the
    /// track end, so it is not the tick grid the fill follows when nothing is
    /// hovering. The shape is Crisp's own slider knob, which is a capsule 20
    /// by 16 at the small control size, not a circle: the system HUD's knob
    /// measures the same way, 8 points wide a half point in from its top edge
    /// where a circle of that height would be 7.
    private static let knobSize = CGSize(width: 18, height: 14)

    private var track: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.07))
                // While the knob is out the fill stops at its leading edge
                // rather than running under it, so the knob sits on the body
                // alone and its own tone lands where the system's does.
                Capsule().fill(.white)
                    .frame(width: model.hovering
                           ? max(0, knobCentre(width) - Self.knobSize.width / 2)
                           : fillWidth(width))
                // The 16-step ticks under the native track: 2 pt dots, 6 pt
                // below its centre line.
                HStack(spacing: 0) {
                    ForEach(0..<17) { tick in
                        Circle().fill(.white.opacity(0.11)).frame(width: 2, height: 2)
                        if tick < 16 { Spacer(minLength: 0) }
                    }
                }
                .padding(.horizontal, Self.tickInset - 1)
                .offset(y: 6)
                if model.hovering {
                    // Not white: measured over five backdrops the system's
                    // knob is white at 0.85 over the capsule body, which reads
                    // 222 on a black backdrop and 247 on a white one where a
                    // flat colour would read the same on both.
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: Self.knobSize.width, height: Self.knobSize.height)
                        .position(x: knobCentre(width), y: 2)
                }
            }
            // The track itself is 4 points tall, which is nothing to aim at,
            // so the drag reads from a band around it.
            .overlay {
                Color.clear
                    .frame(height: 22)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in slide(to: drag.location.x, width: width) }
                    )
            }
        }
        .frame(height: 4)
        // The native track sits a point above the glyph centre line.
        .offset(y: -1)
    }

    /// The knob's centre for the level, on the system's own mapping: the
    /// travel is the track inset by the knob's radius at both ends.
    private func knobCentre(_ width: CGFloat) -> CGFloat {
        let radius = Self.knobSize.width / 2
        return radius + (width - Self.knobSize.width) * max(0, min(1, model.level))
    }

    /// Sets the level from a point on the track, the same mapping back: a
    /// click a quarter of the way along the system's own track set its volume
    /// to 23, not 25, because the knob's travel is what the pointer moves.
    private func slide(to x: CGFloat, width: CGFloat) {
        let radius = Self.knobSize.width / 2
        let travel = max(1, width - Self.knobSize.width)
        let level = max(0, min(1, (x - radius) / travel))
        model.level = level
        model.slide?(level)
    }

    /// The fill ends on the tick for the level, not at a plain fraction of the
    /// track: measured settled on the system HUD, three steps up its fill ends
    /// on the third dot and eleven steps up on the eleventh, to a tenth of a
    /// pixel at 2x. The top of the range is the one exception, where it runs
    /// to the end of the track instead of stopping on the last dot.
    private func fillWidth(_ width: CGFloat) -> CGFloat {
        model.level >= 1 ? width : Self.tickInset + (width - 2 * Self.tickInset) * model.level
    }

    /// Eject never reaches this path (BrightnessKeyService sends only
    /// brightness, volume and mute), it takes the brightness glyphs.
    private var leadingSymbol: String {
        switch model.image {
        case .volume: return "speaker.fill"
        case .mute: return "speaker.slash.fill"
        case .brightness, .eject: return "sun.min.fill"
        }
    }

    /// Mute hides this symbol but keeps its slot, see body.
    private var trailingSymbol: String {
        switch model.image {
        case .volume, .mute: return "speaker.wave.3.fill"
        case .brightness, .eject: return "sun.max.fill"
        }
    }
}
