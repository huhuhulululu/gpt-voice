import SwiftUI

struct OverlayHelpContent: View {
    let notice: DictationOverlayNotice
    let dismiss: () -> Void
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(notice.title).font(AppType.rowTitle)
                Spacer(minLength: 8)
                OverlayIconButton(symbol: "xmark", label: "Dismiss paste help", action: dismiss)
            }
            Text(notice.message)
                .font(AppType.detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle = notice.actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(AppButtonStyle(kind: .secondary, small: true))
                    .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
