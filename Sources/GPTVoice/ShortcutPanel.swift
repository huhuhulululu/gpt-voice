import SwiftUI

/// Keycaps and recorder, quiet presets, then the receipt test. Start and stop are explained by the caller once.
struct ShortcutPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: AppPreferences

    init(model: AppModel) {
        self.model = model
        self.preferences = model.preferences
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroup {
                SettingsRow(title: "Shortcut") {
                    KeycapsView(spec: preferences.hotkey)
                }
                SettingsRow(title: "Change") {
                    ShortcutRecorderField(model: model, isEnabled: model.canChangeSettings)
                        .frame(width: 220, height: 30)
                }
                SettingsRow(title: "Presets") {
                    HStack(spacing: 6) {
                        Button("Left Option") { model.useLeftOption() }
                            .buttonStyle(AppButtonStyle(kind: .secondary, small: true))
                            .disabled(!model.canChangeSettings || model.leftOptionIsActive)
                            .accessibilityLabel("Use Left Option")
                        Button("Command–Space") { model.useCommandSpace() }
                            .buttonStyle(AppButtonStyle(kind: .secondary, small: true))
                            .disabled(!model.canChangeSettings || model.commandSpaceIsActive)
                            .accessibilityLabel("Use Command–Space")
                        Button("Default") { model.resetHotkey() }
                            .buttonStyle(AppButtonStyle(kind: .secondary, small: true))
                            .disabled(!model.canChangeSettings || preferences.hotkey == .default)
                            .accessibilityLabel("Reset to default shortcut")
                    }
                }
                ShortcutTestRow(model: model)
            }

            if let error = model.hotkeyError {
                SettingsGroup {
                    StatusRow(tone: .problem, symbol: "exclamationmark.triangle.fill",
                              title: "That shortcut cannot be used", detail: error) {
                        if model.hotkeyBlockedBySystem {
                            Button("Keyboard settings") { model.openKeyboardShortcutsSettings() }
                                .buttonStyle(AppButtonStyle(kind: .secondary, showsArrow: true, small: true))
                        } else if model.hotkeyNeedsInputMonitoring {
                            Button("Input Monitoring settings") { model.openInputMonitoringSettings() }
                                .buttonStyle(AppButtonStyle(kind: .secondary, showsArrow: true, small: true))
                        }
                    }
                }
            }

            InfoDisclosure(label: "Shortcut not responding?",
                           text: "Another app may use the same keys. Check ChatGPT and System Settings → Keyboard → Keyboard Shortcuts, or choose another shortcut. The recorder cannot capture keys macOS keeps, such as Command–Space — use that preset instead. Hold a key combination to record, then release to transcribe. A short tap still starts; press again to stop. Hold Left Option, or another Option, Control, or Shift key, to record; release pastes the transcript. Using it with another key keeps it a modifier. A modifier-only shortcut needs Input Monitoring in System Settings → Privacy & Security → Input Monitoring. Quit and reopen GPT Voice if a new grant does not take effect.")
        }
        // Never leave a listening test behind when the panel goes away.
        .onDisappear { model.endShortcutTest() }
    }
}
