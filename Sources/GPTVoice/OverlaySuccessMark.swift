import SwiftUI

/// The Pasted check: an 18 pt accent badge that settles from slightly small while a thin ring blooms out once.
/// Reduce Motion shows the badge at rest with no ring.
struct OverlaySuccessMark: View {
    @Environment(\.appAccentChoice) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    var body: some View {
        let dark = colorScheme == .dark
        let increased = contrast == .increased
        ZStack {
            if !reduceMotion {
                Circle()
                    .stroke(LinearGradient(colors: accent.waveRamp(dark: dark),
                                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.3)
                    .frame(width: 21, height: 21)
                    .scaleEffect(settled ? 1.5 : 1)
                    .opacity(settled ? 0 : 0.5)
                    .animation(.easeOut(duration: 0.55), value: settled)
            }
            badge(dark: dark, increased: increased)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(increased ? accent.onFill : Color.white.opacity(0.97))
                )
                .frame(width: 18, height: 18)
                .scaleEffect(reduceMotion || settled ? 1 : 0.86)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: settled)
        }
        .frame(width: 18, height: 18)
        .onAppear { settled = true }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func badge(dark: Bool, increased: Bool) -> some View {
        if increased {
            Circle().fill(accent.color)
        } else {
            Circle()
                .fill(LinearGradient(colors: accent.buttonRamp(dark: dark), startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().fill(OverlayGloss.gradient))
        }
    }
}
