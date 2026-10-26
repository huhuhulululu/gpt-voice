import Foundation

/// Overlay callbacks. The Appearance preview passes `.preview`, which does nothing.
struct DictationOverlayActions {
    var stop: () -> Void
    var cancel: () -> Void
    var dismiss: () -> Void
    var recover: () -> Void

    static let preview = DictationOverlayActions(stop: {}, cancel: {}, dismiss: {}, recover: {})
}
