import SwiftUI

/// Input Monitoring row. Shown when the shortcut is a modifier hold, or when that grant is blocking it.
struct InputMonitoringCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.hotkeyNeedsInputMonitoring || (model.preferences.hotkey.isModifierHold && !InputMonitoringPermission.isGranted) {
            StatusRow(tone: .attention, symbol: "exclamationmark.circle.fill", title: "Input Monitoring",
                      detail: "Required to hold a modifier, such as Left Option, as the shortcut.") {
                Button("Open Settings") { model.openInputMonitoringSettings() }
                    .buttonStyle(AppButtonStyle(kind: .secondary, small: true))
                    .accessibilityLabel("Open Input Monitoring settings")
                QuietIconButton(symbol: "arrow.clockwise", label: "Check Input Monitoring again") {
                    model.refreshStatus()
                }
            }
        } else if model.preferences.hotkey.isModifierHold {
            StatusRow(tone: .good, symbol: "checkmark.circle.fill", title: "Input Monitoring",
                      detail: "Lets a modifier-only shortcut start recording.", value: "Allowed") { EmptyView() }
        }
    }
}
