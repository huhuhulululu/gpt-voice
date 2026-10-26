import Foundation

/// Distinguishes a tap from a hold on a Carbon key-combination shortcut.
/// A tap keeps toggle behavior. A hold stops recording when the key comes up.
enum CombinationHoldWatch {
    /// Wait long enough to see whether the key stayed down after the hotkey press.
    static let grace: TimeInterval = 0.08
    static let poll: TimeInterval = 0.03

    enum Decision: Equatable {
        case treatAsTap
        case beginHold
        case finishHold
        case ignore
    }

    static func afterGrace(keyStillDown: Bool) -> Decision {
        keyStillDown ? .beginHold : .treatAsTap
    }

    static func whileHolding(keyStillDown: Bool) -> Decision {
        keyStillDown ? .ignore : .finishHold
    }
}
