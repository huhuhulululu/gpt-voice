import AppKit
import SwiftUI

/// Frosted glass for the recording bar and its help card: the system material, a soft neutral tint
/// (white on light, charcoal on dark, never pure black or white), a 0.5 pt hairline and a lighter inner rim.
/// Reduce Transparency and Increase Contrast get a solid surface; Increase Contrast also gets a stronger edge.
struct OverlaySurface: ViewModifier {
    let cornerRadius: CGFloat
    /// `.behindWindow` for the live panel. `.withinWindow` for previews and measuring, which also draw
    /// their own soft shadow; the live panel uses the window shadow.
    var blending: NSVisualEffectView.BlendingMode = .withinWindow
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
        let dark = colorScheme == .dark
        let increased = contrast == .increased
        content
            .background {
                if reduceTransparency || increased {
                    shape.fill(AppPalette.surface)
                } else {
                    ZStack {
                        OverlayGlassMaterial(cornerRadius: cornerRadius, blending: blending)
                        shape.fill(LinearGradient(colors: tint(dark: dark), startPoint: .top, endPoint: .bottom))
                    }
                }
            }
            .overlay {
                if increased {
                    shape.strokeBorder(Color.primary.opacity(0.5), lineWidth: 1.5)
                } else {
                    ZStack {
                        shape.strokeBorder(Color.black.opacity(dark ? 0.3 : 0.075), lineWidth: 0.5)
                        shape.inset(by: 0.5)
                            .strokeBorder(LinearGradient(stops: rim(dark: dark), startPoint: .top, endPoint: .bottom),
                                          lineWidth: 0.5)
                    }
                }
            }
            .clipShape(shape)
            .shadow(color: Color.black.opacity(blending == .withinWindow && !increased ? (dark ? 0.3 : 0.1) : 0),
                    radius: 9, y: 4)
    }

    /// Laid over the system material, which already blurs and lightens or darkens what is behind.
    private func tint(dark: Bool) -> [Color] {
        dark
            ? [AppPalette.color(0x3A3A42).opacity(0.34), AppPalette.color(0x2B2B32).opacity(0.46)]
            : [Color.white.opacity(0.4), AppPalette.color(0xFBFBFD).opacity(0.24)]
    }

    private func rim(dark: Bool) -> [Gradient.Stop] {
        dark
            ? [.init(color: .white.opacity(0.17), location: 0), .init(color: .white.opacity(0.04), location: 0.5),
               .init(color: .white.opacity(0.02), location: 1)]
            : [.init(color: .white.opacity(0.95), location: 0), .init(color: .white.opacity(0.3), location: 0.5),
               .init(color: .white.opacity(0.15), location: 1)]
    }
}
