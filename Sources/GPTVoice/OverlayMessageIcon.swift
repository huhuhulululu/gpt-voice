import SwiftUI

/// The 16 pt leading mark on a recording bar message. Warnings get a soft coral disc that stays the same
/// in every colorway; no-speech and paste hints get a quiet secondary symbol.
struct OverlayMessageIcon: View {
    let kind: OverlayMessageKind

    var body: some View {
        Group {
            switch kind {
            case .warning:
                Circle()
                    .fill(OverlayInk.warningFill)
                    .overlay(
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(OverlayInk.warningMark)
                    )
            case .noSpeech:
                Image(systemName: "waveform.slash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OverlayInk.secondary)
            case .info:
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OverlayInk.secondary)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}
