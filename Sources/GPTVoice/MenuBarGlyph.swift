import AppKit

/// The menu bar mark: the five-bar Goice wave on an 18 pt template image, so macOS inks it for light,
/// dark and highlighted menu bars. Listening stands taller, working cycles three frames, and needs
/// attention dims the bars under a small dot.
enum MenuBarGlyph {
    enum Style: Equatable {
        case idle
        case listening
        case working(frame: Int)
        case attention
    }

    static let workingFrameCount = 3
    static let workingFrameInterval: TimeInterval = 0.12
    /// The working frame shown still under Reduce Motion.
    static let restingWorkingFrame = 1

    private static let size = NSSize(width: 18, height: 18)
    private static let barX: [CGFloat] = [1, 4.5, 8, 11.5, 15]
    private static let barWidth: CGFloat = 2
    private static let idleHeights: [CGFloat] = [6, 10, 14, 8, 4]
    private static let listeningHeights: [CGFloat] = [8, 12, 16, 10, 6]
    private static let workingHeights: [[CGFloat]] = [[4, 6, 10, 6, 4], [4, 8, 12, 8, 4], [6, 10, 8, 10, 6]]

    static func image(_ style: Style, accessibilityDescription: String) -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            draw(style)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    private static func draw(_ style: Style) {
        let heights: [CGFloat]
        var barAlpha: CGFloat = 1
        switch style {
        case .idle:
            heights = idleHeights
        case .listening:
            heights = listeningHeights
        case .working(let frame):
            heights = workingHeights[((frame % workingFrameCount) + workingFrameCount) % workingFrameCount]
        case .attention:
            heights = idleHeights
            barAlpha = 0.45
        }
        NSColor.black.withAlphaComponent(barAlpha).setFill()
        for (x, height) in zip(barX, heights) {
            let bar = NSRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
            NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        }
        if style == .attention {
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 13.25, y: 0.5, width: 4.5, height: 4.5)).fill()
        }
    }
}
