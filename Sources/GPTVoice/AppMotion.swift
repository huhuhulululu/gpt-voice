import SwiftUI

/// Motion tokens. Short and settled. No bounce anywhere. Reduce Motion removes movement.
enum AppMotion {
    /// Overlay first appears slightly small, then settles. Reduce Motion stays at 1.
    static let overlayEntranceScale: CGFloat = 0.96
    /// Overlay leaves a little smaller than it entered. Reduce Motion stays at 1.
    static let overlayExitScale: CGFloat = 0.98

    /// Hover, press, toggle, segment: 0.16 s ease-out.
    static func control(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.16)
    }

    /// Page and step changes: a 0.22 s cross-fade. Movement stays at 6 pt or less.
    static func reveal(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeOut(duration: 0.1) : .easeOut(duration: 0.22)
    }

    /// Overlay fade, scale, and width. Reduce Motion keeps a short fade only.
    static func overlay(_ reduceMotion: Bool, duration: TimeInterval, reduced: TimeInterval) -> Animation {
        .easeOut(duration: reduceMotion ? reduced : duration)
    }
}
