import SwiftUI

/// Content and padding for each bar state, shared by the live resizing panel and the measuring and preview views,
/// so both produce the same size. Listening stays wider than working, so release always resizes visibly.
struct OverlayCapsuleContent: View {
    let state: DictationOverlayState
    let actions: DictationOverlayActions
    /// A fixed waveform for the Appearance preview. nil follows the live level.
    var sampleWaveform: [CGFloat]? = nil

    @ViewBuilder var body: some View {
        switch state {
        case .recording(let elapsed, let level):
            HStack(spacing: 0) {
                OverlayLiveDot(level: level, animates: sampleWaveform == nil)
                    .padding(.trailing, 7)
                OverlayWaveform(level: level, elapsed: elapsed, sample: sampleWaveform)
                    .padding(.trailing, 10)
                Text(DictationOverlayState.format(elapsed))
                    .font(AppType.timer)
                    .monospacedDigit()
                    .foregroundStyle(OverlayInk.secondary)
                    .fixedSize()
                    .accessibilityLabel("Elapsed \(DictationOverlayState.format(elapsed))")
                    .padding(.trailing, 10)
                OverlayIconButton(symbol: "xmark", label: "Cancel dictation", action: actions.cancel)
                    .padding(.trailing, 5)
                OverlayIconButton(symbol: "stop.fill", label: "Stop and transcribe", prominent: true, action: actions.stop)
            }
            .padding(.leading, 12)
            .padding(.trailing, 5)
        case .working(let label, let cancellable):
            HStack(spacing: 0) {
                OverlayFlowDots()
                    .padding(.trailing, 10)
                Text(label)
                    .font(AppType.overlayLabel)
                    .foregroundStyle(OverlayInk.primary)
                    .lineLimit(1)
                    .frame(minWidth: 92, alignment: .leading)
                    .padding(.trailing, 10)
                // Transcribing and Pasting share one measured size, so the cancel slot stays when it cannot cancel.
                if cancellable {
                    OverlayIconButton(symbol: "xmark", label: "Cancel dictation", action: actions.cancel)
                } else {
                    Color.clear.frame(width: 24, height: 24)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 7)
        case .success(let label):
            HStack(spacing: 8) {
                OverlaySuccessMark()
                Text(label)
                    .font(AppType.overlayLabel)
                    .foregroundStyle(OverlayInk.primary)
                    .lineLimit(1)
            }
            .padding(.leading, 11)
            .padding(.trailing, 16)
        case .message(let label, let kind, let actionTitle):
            HStack(spacing: 0) {
                OverlayMessageIcon(kind: kind)
                    .padding(.trailing, 8)
                Text(label)
                    .font(AppType.overlayLabel)
                    .foregroundStyle(OverlayInk.primary)
                    .lineLimit(1)
                if let actionTitle {
                    OverlayActionPill(title: actionTitle, action: actions.recover)
                        .padding(.leading, 12)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, actionTitle == nil ? 16 : 6)
        case .hidden, .notice:
            EmptyView()
        }
    }
}
