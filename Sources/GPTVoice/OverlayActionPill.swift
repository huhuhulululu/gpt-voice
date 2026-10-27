import SwiftUI

/// The one text action on a recording bar message, such as Retry or Open Settings.
/// The accent ramp with a white semibold label. Increase Contrast uses the solid accent fill.
struct OverlayActionPill: View {
    let title: String
    let action: () -> Void
    @Environment(\.appAccentChoice) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let increased = contrast == .increased
        Button(action: action) {
            Text(title)
                .font(AppType.overlayAction)
                .foregroundStyle(increased ? accent.onFill : Color.white.opacity(0.97))
                .shadow(color: Color.black.opacity(increased ? 0 : 0.12), radius: 0.5, y: 0.5)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 13)
                .frame(height: 26)
                .background(fill(increased: increased))
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleButtonStyle())
        .help(title)
        .accessibilityLabel(title)
    }

    @ViewBuilder private func fill(increased: Bool) -> some View {
        if increased {
            Capsule().fill(accent.color)
        } else {
            Capsule()
                .fill(LinearGradient(colors: accent.fillRamp(dark: colorScheme == .dark),
                                     startPoint: .leading, endPoint: .trailing))
                .overlay(Capsule().fill(OverlayGloss.gradient))
        }
    }
}
