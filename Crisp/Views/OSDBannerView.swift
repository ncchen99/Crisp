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
}

/// The banner OSDBannerService draws on macOS 26: the display name over a
/// level track with a symbol at each end, in the style of the system's own
/// brightness and volume capsule under the menu bar. Sizes and paddings are
/// tuned against a screenshot of the native capsule on the same screen.
@available(macOS 26.0, *)
struct OSDBannerView: View {
    /// Visible capsule size, measured from the native HUD on 26.5.1.
    static let size = CGSize(width: 290, height: 63)

    @ObservedObject var model: OSDBannerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(model.title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: leadingSymbol)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                track
                Image(systemName: trailingSymbol)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    // Mute keeps the slot so the track does not grow 27 pt.
                    .opacity(model.image == .mute ? 0 : 1)
            }
        }
        .padding(.horizontal, 15)
        .padding(.top, 10)
        .padding(.bottom, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var track: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.07))
                Capsule().fill(.white).frame(width: geo.size.width * model.level)
                // The 16-step ticks under the native track: 2 pt dots, 6 pt
                // below its centre line, 5 pt in from each end.
                HStack(spacing: 0) {
                    ForEach(0..<17) { tick in
                        Circle().fill(.white.opacity(0.11)).frame(width: 2, height: 2)
                        if tick < 16 { Spacer(minLength: 0) }
                    }
                }
                .padding(.horizontal, 5)
                .offset(y: 6)
            }
        }
        .frame(height: 4)
        // The native track sits a point above the glyph centre line.
        .offset(y: -1)
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
