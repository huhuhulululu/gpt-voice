import Foundation

/// A larger overlay card for a recovery that needs more than a one-line pill.
struct DictationOverlayNotice: Equatable {
    let title: String
    let message: String
    var actionTitle: String? = nil
}
