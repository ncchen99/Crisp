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
    static let size = NSSize(width: 280, height: 54)

    @ObservedObject var model: OSDBannerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 8) {
                Image(systemName: leadingSymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                track
                if let trailingSymbol {
                    Image(systemName: trailingSymbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var track: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.3))
                Capsule().fill(.primary).frame(width: geo.size.width * model.level)
            }
        }
        .frame(height: 6)
    }

    private var leadingSymbol: String {
        switch model.image {
        case .volume: return "speaker.fill"
        case .mute: return "speaker.slash.fill"
        default: return "sun.min.fill"
        }
    }

    /// Mute shows the slashed speaker alone with an empty track.
    private var trailingSymbol: String? {
        switch model.image {
        case .volume: return "speaker.wave.3.fill"
        case .mute: return nil
        default: return "sun.max.fill"
        }
    }
}
