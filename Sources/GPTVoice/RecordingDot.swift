import SwiftUI

/// The live recording mark. Pulses only while the input is quiet. Speech holds it solid.
struct RecordingDot: View {
    var level: Float = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    private var speaking: Bool { level >= 0.08 }

    var body: some View {
        Circle()
            .fill(AppPalette.recording)
            .frame(width: 7, height: 7)
            .opacity(reduceMotion || speaking ? 1 : (dimmed ? 0.5 : 1))
            .animation(reduceMotion ? nil : .easeInOut(duration: 1.25).repeatForever(autoreverses: true),
                       value: dimmed)
            .onAppear { dimmed = !reduceMotion }
            .accessibilityLabel("Recording")
    }
}
