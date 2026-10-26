import SwiftUI

/// Compact settings field. Matches the recessed well used by segmented controls.
struct AppTextField: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var secure = false

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(AppType.body)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(minWidth: 200)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(AppPalette.well))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(AppPalette.hairline))
        .accessibilityLabel(label)
    }
}
