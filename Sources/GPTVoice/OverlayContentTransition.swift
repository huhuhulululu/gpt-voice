import SwiftUI

enum OverlayContentTransition {
    /// Cross-fade only. Blur was expensive on the overlay's first frame.
    /// Reduce Motion swaps instantly; the adjacent label still names the state.
    static func transition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : .opacity
    }
}
