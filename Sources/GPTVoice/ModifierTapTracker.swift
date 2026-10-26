import Foundation

/// Decides when a press and release of one modifier key is a tap.
/// A chord, click, or scroll cancels it, so the key still works as a modifier.
struct ModifierTapTracker {
    /// Long enough for a deliberate tap. A longer hold is not a shortcut.
    static let defaultMaximumDuration: TimeInterval = 1

    let keyCode: UInt32
    var maximumDuration: TimeInterval
    private var pressedAt: TimeInterval?

    init(keyCode: UInt32, maximumDuration: TimeInterval = defaultMaximumDuration) {
        self.keyCode = keyCode
        self.maximumDuration = maximumDuration
    }

    mutating func reset() {
        pressedAt = nil
    }

    /// Returns true when `event` completes a clean tap of `keyCode`.
    mutating func consume(eventKeyCode: UInt32?, modifierDown: Bool, otherModifierDown: Bool,
                          timestamp: TimeInterval, cancelsTap: Bool) -> Bool {
        if cancelsTap || otherModifierDown {
            reset()
            return false
        }
        guard eventKeyCode == keyCode else { return false }
        if modifierDown {
            pressedAt = timestamp
            return false
        }
        defer { reset() }
        guard let pressedAt, timestamp >= pressedAt else { return false }
        return timestamp - pressedAt <= maximumDuration
    }
}
