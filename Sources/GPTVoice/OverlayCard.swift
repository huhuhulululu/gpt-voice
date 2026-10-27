import SwiftUI

/// The first manual-paste explanation. Later results use a compact message.
struct OverlayCard: View {
    let notice: DictationOverlayNotice
    let actions: DictationOverlayActions

    var body: some View {
        OverlayHelpContent(notice: notice, dismiss: actions.dismiss,
                           action: notice.actionTitle == nil ? nil : actions.recover)
            .modifier(OverlaySurface(cornerRadius: OverlayMetrics.helpCornerRadius))
    }
}
