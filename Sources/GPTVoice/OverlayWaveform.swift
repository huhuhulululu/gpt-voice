import SwiftUI

/// Scrolling input level: 13 bars, newest on the right, colored along the accent ramp. Older bars fade
/// on light glass and drift toward gray on dark glass. Driven only by the real level: silence shows short
/// flat bars. Each bar holds the loudest level of its 0.1 s slot, so short syllables still register.
/// Reduce Motion stops the scroll and shapes every bar from the current level instead.
struct OverlayWaveform: View {
    let level: Float
    let elapsed: TimeInterval
    /// A fixed history for the Appearance preview. nil follows the live level.
    var sample: [CGFloat]?

    @State private var history = Array(repeating: CGFloat(0), count: Self.count)
    @State private var slot = -1
    @Environment(\.appAccentChoice) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let count = 13
    private static let barWidth: CGFloat = 3
    private static let gap: CGFloat = 2
    private static let minimumHeight: CGFloat = 3.5
    private static let maximumHeight: CGFloat = 20
    private static let slotLength: TimeInterval = 0.1
    /// Room for the glow around the bars.
    private static let bleed: CGFloat = 3
    static let width = CGFloat(count) * barWidth + CGFloat(count - 1) * gap
    /// Taller in the middle, for the Reduce Motion meter.
    private static let profile: [CGFloat] = [0.45, 0.55, 0.65, 0.75, 0.85, 0.95, 1, 0.95, 0.85, 0.75, 0.65, 0.55, 0.45]

    /// Speech-like levels for the Appearance preview.
    static let previewSample: [CGFloat] = [0.10, 0.18, 0.34, 0.60, 0.44, 0.74, 0.92, 0.62, 0.82, 0.50, 0.68, 0.40, 0.56]

    var body: some View {
        Canvas { context, size in
            draw(bars, in: &context, size: size)
        }
        .frame(width: Self.width + 2 * Self.bleed, height: Self.maximumHeight + 2 * Self.bleed)
        .padding(-Self.bleed)
        .onChange(of: elapsed) { newElapsed in advance(to: newElapsed) }
        .onChange(of: level) { newLevel in
            history[Self.count - 1] = max(history[Self.count - 1], CGFloat(newLevel))
        }
        .accessibilityElement()
        .accessibilityLabel("Input level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }

    private var bars: [CGFloat] {
        if let sample { return sample }
        if reduceMotion { return Self.profile.map { $0 * CGFloat(level) } }
        return history
    }

    private func advance(to elapsed: TimeInterval) {
        let next = Int(elapsed / Self.slotLength)
        if next < slot {
            history = Array(repeating: 0, count: Self.count)
        } else if next == slot {
            return
        }
        slot = next
        history.removeFirst()
        history.append(CGFloat(level))
    }

    private struct Bar {
        var rect: CGRect
        var color: Color
        var opacity: CGFloat
        var glow: CGFloat
    }

    private func draw(_ levels: [CGFloat], in context: inout GraphicsContext, size: CGSize) {
        let dark = colorScheme == .dark
        let increased = contrast == .increased
        let stops = accent.waveStops(dark: dark)
        let last = CGFloat(max(1, levels.count - 1))
        var bars: [Bar] = []
        for (index, value) in levels.enumerated() {
            let loud = CGFloat(pow(Double(max(0, min(1, value))), 0.8))
            let height = Self.minimumHeight + (Self.maximumHeight - Self.minimumHeight) * loud
            let age = 1 - CGFloat(index) / last
            let x = Self.bleed + CGFloat(index) * (Self.barWidth + Self.gap)
            var hex = AppPalette.sample(stops, at: Double((x - Self.bleed + Self.barWidth / 2) / Self.width))
            var opacity: CGFloat
            if dark {
                hex = AppPalette.mix(hex, 0xA9A9B4, 0.6 * pow(Double(age), 1.2))
                opacity = 1 - 0.5 * CGFloat(pow(Double(age), 1.25))
            } else {
                opacity = 1 - 0.7 * CGFloat(pow(Double(age), 1.25))
            }
            if increased { opacity = max(opacity, 0.8) }
            bars.append(Bar(rect: CGRect(x: x, y: size.height / 2 - height / 2, width: Self.barWidth, height: height),
                            color: AppPalette.color(hex),
                            opacity: opacity,
                            glow: increased ? 0 : 0.65 * loud * (1 - age)))
        }

        context.drawLayer { glow in
            glow.addFilter(.blur(radius: 3.2))
            for bar in bars where bar.glow > 0.01 {
                let rect = bar.rect.insetBy(dx: -0.5, dy: -0.5)
                glow.fill(Path(roundedRect: rect, cornerRadius: rect.width / 2), with: .color(bar.color.opacity(bar.glow)))
            }
        }
        for bar in bars {
            context.fill(Path(roundedRect: bar.rect, cornerRadius: Self.barWidth / 2),
                         with: .color(bar.color.opacity(bar.opacity)))
        }
    }
}
