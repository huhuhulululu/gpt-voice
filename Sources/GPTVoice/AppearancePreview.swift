import SwiftUI

/// The real recording bar views in two sample states, on the window's own glass. No microphone use.
/// The live dot breathes and the dots flow, so the selected colorway shows in motion.
struct AppearancePreview: View {
    private static let recording = DictationOverlayState.recording(elapsed: 4, level: 0.56)
    private static let working = DictationOverlayState.working(label: "Transcribing…", cancellable: true)

    var body: some View {
        HStack(spacing: 12) {
            DictationOverlayView(state: Self.recording, actions: .preview, sampleWaveform: OverlayWaveform.previewSample)
            DictationOverlayView(state: Self.working, actions: .preview)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sample recording bar")
    }
}
