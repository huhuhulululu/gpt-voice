import SwiftUI

/// Round icon buttons for the recording bar. Always has an accessible name.
/// Quiet: 24 pt, a faint neutral disc. Prominent (stop): 28 pt, the accent ramp with a white glyph and a soft glow.
/// Increase Contrast swaps the ramp for the solid accent fill and darkens the quiet disc.
struct OverlayIconButton: View {
    let symbol: String
    let label: String
    var prominent = false
    let action: () -> Void
    @Environment(\.appAccentChoice) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let edge: CGFloat = prominent ? 28 : 24
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 10 : 9.5, weight: .bold))
                .foregroundStyle(glyph)
                .frame(width: edge, height: edge)
                .background(disc)
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }

    private var increased: Bool { contrast == .increased }

    private var glyph: Color {
        if prominent { return increased ? accent.onFill : Color.white.opacity(0.96) }
        return increased ? Color.primary : OverlayInk.controlGlyph
    }

    @ViewBuilder private var disc: some View {
        if prominent && increased {
            Circle().fill(accent.color)
        } else if prominent {
            let dark = colorScheme == .dark
            Circle()
                .fill(LinearGradient(colors: accent.buttonRamp(dark: dark), startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().fill(OverlayGloss.gradient))
                .shadow(color: AppPalette.color(accent.buttonStops(dark: dark)[1]).opacity(0.45), radius: 3, y: 1.5)
        } else {
            Circle().fill(increased ? Color.primary.opacity(0.14) : OverlayInk.controlFill)
        }
    }
}
