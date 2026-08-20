import AppKit
import SwiftUI

/// Panel chrome colours. Tuned to the light-mode reference design while still adapting to dark.
enum Palette {
    static let panelBackground = Color(nsColor: dynamic(light: 0.929, dark: 0.129))
    static let railBackground = Color(nsColor: dynamic(light: 0.949, dark: 0.157))
    static let cardBackground = Color(nsColor: dynamic(light: 0.973, dark: 0.204))
    static let fieldBackground = Color(nsColor: dynamic(light: 1.0, dark: 0.235))
    static let hairline = Color(nsColor: dynamic(light: 0.855, dark: 0.267))
    static let primaryText = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)

    static let panelCornerRadius: CGFloat = 14
    static let railWidth: CGFloat = 48
    static let railCollapsedWidth: CGFloat = 20

    private static func dynamic(light: CGFloat, dark: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(white: isDark ? dark : light, alpha: 1)
        }
    }
}

/// Fallback site glyph used until a favicon arrives (or when the site has none).
struct SiteMonogram: View {
    let site: Site
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(color)
            .overlay(
                Text(site.initials)
                    .font(.system(size: size * 0.52, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
    }

    private var color: Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .indigo, .red]
        return palette[Self.paletteIndex(for: site.host, count: palette.count)].opacity(0.85)
    }

    /// Swift seeds `hashValue` per process, so using it here made a site's fallback icon
    /// change colour on every launch. FNV-1a keeps it stable.
    static func paletteIndex(for host: String, count: Int) -> Int {
        var hash: UInt32 = 2_166_136_261
        for byte in host.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return Int(hash % UInt32(count))
    }
}

struct SiteIconView: View {
    let site: Site
    let size: CGFloat
    @ObservedObject var favicons: FaviconService

    var body: some View {
        Group {
            if let icon = favicons.icon(for: site) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                SiteMonogram(site: site, size: size)
            }
        }
        // Fetching from the body would mutate published state mid-render.
        .task(id: site.host) { await favicons.load(for: site) }
    }
}
