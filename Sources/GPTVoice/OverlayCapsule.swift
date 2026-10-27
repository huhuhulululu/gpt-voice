import SwiftUI

/// The compact static bar, for the Appearance preview and for measuring. The live panel owns one
/// continuously resizing surface instead.
struct OverlayCapsule: View {
    let state: DictationOverlayState
    let actions: DictationOverlayActions
    var sampleWaveform: [CGFloat]? = nil

    var body: some View {
        OverlayCapsuleContent(state: state, actions: actions, sampleWaveform: sampleWaveform)
            .frame(height: OverlayMetrics.height)
            .fixedSize(horizontal: true, vertical: false)
            .modifier(OverlaySurface(cornerRadius: OverlayMetrics.cornerRadius))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Dictation status")
    }
}
