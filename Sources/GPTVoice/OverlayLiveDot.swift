import SwiftUI

/// The live recording mark: a soft accent orb whose halo breathes on a 1.6 s loop.
/// Louder input brightens the glow. Reduce Motion holds the halo still at half breath.
struct OverlayLiveDot: View {
    var level: Float = 0
    @Environment(\.appAccentChoice) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let size: CGFloat = 16
    /// Room for the blurred glow around the 16 pt layout box.
    private static let bleed: CGFloat = 8
    private static let core: CGFloat = 4
    private static let period: TimeInterval = 1.6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                draw(in: &context, size: size, breath: breath(at: timeline.date))
            }
        }
        .frame(width: Self.size + 2 * Self.bleed, height: Self.size + 2 * Self.bleed)
        .padding(-Self.bleed)
        .accessibilityElement()
        .accessibilityLabel("Recording")
    }

    private func breath(at date: Date) -> CGFloat {
        if reduceMotion { return 0.5 }
        let phase = date.timeIntervalSinceReferenceDate / Self.period
        return CGFloat(0.5 - 0.5 * cos(2 * .pi * phase))
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, breath: CGFloat) {
        let stops = accent.waveStops(dark: colorScheme == .dark)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let core = Self.core
        let loud = CGFloat(max(0, min(1, level)))

        context.drawLayer { glow in
            glow.addFilter(.blur(radius: 3.2))
            glow.fill(circle(center, core + 1.5 + 3.2 * breath),
                      with: .color(AppPalette.color(stops[0]).opacity(min(1, 0.3 + 0.45 * breath + 0.2 * loud))))
        }
        context.fill(circle(center, core + 1.6 + 2.8 * breath),
                     with: .color(AppPalette.color(stops[1]).opacity(0.24 - 0.1 * breath)))
        let highlight = AppPalette.mix(stops[0], 0xFFFFFF, 0.3)
        context.fill(circle(center, core),
                     with: .radialGradient(Gradient(colors: [AppPalette.color(highlight), AppPalette.color(stops[1])]),
                                           center: CGPoint(x: center.x - 1.2, y: center.y - 1.4),
                                           startRadius: 0.2, endRadius: core))
    }

    private func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}
