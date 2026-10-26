import SwiftUI

/// The live recording mark. A slow opacity pulse; Reduce Motion keeps it solid.
struct RecordingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(AppPalette.recording)
            .frame(width: 7, height: 7)
            .opacity(reduceMotion ? 1 : (dimmed ? 0.45 : 1))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                       value: dimmed)
            .onAppear { dimmed = !reduceMotion }
            .accessibilityLabel("Recording")
    }
}
