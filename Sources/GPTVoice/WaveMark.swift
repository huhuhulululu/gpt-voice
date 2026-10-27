import SwiftUI

/// App mark, matching app icon A: a dark rounded tile with coral-to-violet voice bars, the same in both themes.
/// Below 24 pt it uses the icon's three-bar small mark so the bars stay distinct.
struct WaveMark: View {
    var size: CGFloat = 20

    private static let fullProfile: [CGFloat] = [0.42, 0.72, 1.0, 0.58, 0.30]
    private static let smallProfile: [CGFloat] = [0.62, 1.0, 0.5]
    private static let tile = LinearGradient(colors: [AppPalette.color(0x3A3A43), AppPalette.color(0x121216)],
                                             startPoint: .top, endPoint: .bottom)
    private static let bars = LinearGradient(colors: [AppPalette.color(0xFF8A5B), AppPalette.color(0xFF4F7B),
                                                      AppPalette.color(0x9B6BFF)],
                                             startPoint: .leading, endPoint: .trailing)

    var body: some View {
        let small = size < 24
        let profile = small ? Self.smallProfile : Self.fullProfile
        let barWidth = size * (small ? 0.13 : 0.085)
        let gap = size * (small ? 0.09 : 0.062)
        let maxHeight = size * (small ? 0.58 : 0.56)
        let total = CGFloat(profile.count) * barWidth + CGFloat(profile.count - 1) * gap
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(Self.tile)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .frame(width: size, height: size)
            .overlay(
                // One ramp across all bars, as in the icon, rather than a full ramp inside each bar.
                Self.bars
                    .frame(width: total, height: maxHeight)
                    .mask {
                        HStack(alignment: .center, spacing: gap) {
                            ForEach(Array(profile.enumerated()), id: \.offset) { _, share in
                                Capsule().frame(width: barWidth, height: maxHeight * share)
                            }
                        }
                    }
            )
            .accessibilityHidden(true)
    }
}
