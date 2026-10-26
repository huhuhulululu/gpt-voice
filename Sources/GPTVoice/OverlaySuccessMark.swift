import SwiftUI

/// A short settle on the success check. Reduce Motion shows the mark at rest.
struct OverlaySuccessMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(AppPalette.success)
            .scaleEffect(reduceMotion || settled ? 1 : 0.86)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: settled)
            .onAppear { settled = true }
            .accessibilityHidden(true)
    }
}
