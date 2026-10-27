import CoreGraphics

/// Recording bar geometry. The live panel and the measuring view both read these, so their sizes match.
enum OverlayMetrics {
    static let height: CGFloat = 38
    /// A full capsule. The glass mask and the SwiftUI shape both use circular corners so their edges agree.
    static let cornerRadius: CGFloat = height / 2
    /// The manual-paste help card.
    static let helpCornerRadius: CGFloat = 14
}
