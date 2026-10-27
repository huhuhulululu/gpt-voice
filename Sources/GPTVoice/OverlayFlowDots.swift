import SwiftUI

/// Transcribing and Pasting: five accent dots with a wave running through them left to right on a 1.1 s loop.
/// Reduce Motion holds them still; the label beside them names the state.
struct OverlayFlowDots: View {
    @Environment(\.appAccentChoice) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let count = 5
    private static let diameter: CGFloat = 4.6
    private static let step: CGFloat = 7
    private static let period: TimeInterval = 1.1
    /// Room for the glow and the rise of each dot.
    private static let bleed: CGFloat = 5
    static let width = diameter + CGFloat(count - 1) * step

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                draw(phase: timeline.date.timeIntervalSinceReferenceDate / Self.period, in: &context, size: size)
            }
        }
        .frame(width: Self.width + 2 * Self.bleed, height: 20)
        .padding(.horizontal, -Self.bleed)
        .accessibilityHidden(true)
    }

    private func draw(phase: Double, in context: inout GraphicsContext, size: CGSize) {
        let ramp = Gradient(colors: accent.waveRamp(dark: colorScheme == .dark))
        let shading = GraphicsContext.Shading.linearGradient(ramp, startPoint: CGPoint(x: Self.bleed, y: 0),
                                                             endPoint: CGPoint(x: Self.bleed + Self.width, y: 0))
        let glows = contrast != .increased
        for index in 0..<Self.count {
            let swell = reduceMotion ? 0.6 : CGFloat(0.5 + 0.5 * sin(2 * .pi * (phase - Double(index) / Double(Self.count))))
            let radius = Self.diameter / 2 * (0.72 + 0.42 * swell)
            let center = CGPoint(x: Self.bleed + Self.diameter / 2 + CGFloat(index) * Self.step,
                                 y: size.height / 2 - 1.8 * swell + 0.9)
            if glows {
                context.drawLayer { glow in
                    glow.addFilter(.blur(radius: 3.2))
                    glow.opacity = Double(0.55 * swell)
                    glow.fill(circle(center, radius + 1.2), with: shading)
                }
            }
            var dot = context
            dot.opacity = Double(glows ? 0.38 + 0.62 * swell : 0.7 + 0.3 * swell)
            dot.fill(circle(center, radius), with: shading)
        }
    }

    private func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}
