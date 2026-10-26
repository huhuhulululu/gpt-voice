import SwiftUI

/// Automatic paste, sound cues, and launch at login. Short labels. A detail only when it changes a decision.
struct BehaviorSection: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: AppPreferences

    init(model: AppModel) {
        self.model = model
        self.preferences = model.preferences
    }

    private var showsLoginIssue: Bool {
        model.launchAtLoginError != nil || model.launchAtLogin == .requiresApproval
    }

    private var pasteDetail: String {
        if !preferences.automaticPaste {
            return "Keeps the transcript on the clipboard so you can press ⌘V."
        }
        if model.accessibilityTrusted {
            return "Inserts or pastes into the focused field, then restores your clipboard."
        }
        return "Needs Accessibility on Home or Privacy. Until then, text is copied."
    }

    var body: some View {
        SettingsGroup {
            SettingsRow(title: "Paste into the focused field",
                        detail: pasteDetail) {
                AppToggle(label: "Paste into the focused field",
                          isOn: Binding(get: { preferences.automaticPaste }, set: { model.setAutomaticPaste($0) }))
                    .disabled(!model.canChangeSettings)
            }
            if preferences.automaticPaste, !model.accessibilityTrusted {
                StatusRow(tone: .neutral, symbol: "circle.dashed", title: "Accessibility is off",
                          detail: "Allow it so \(AppBrand.displayName) can paste for you. Or leave paste off and press ⌘V.") {
                    Button("Allow") { model.requestAccessibility() }
                        .buttonStyle(AppButtonStyle(kind: .secondary, small: true))
                        .accessibilityLabel("Allow Accessibility")
                    Button("Open Settings") { model.openAccessibilitySettings() }
                        .buttonStyle(AppButtonStyle(kind: .quiet, small: true))
                        .accessibilityLabel("Open Accessibility settings")
                }
            }
            SettingsRow(title: "Sound cues",
                        detail: "A short click when recording starts and when you release.") {
                AppToggle(label: "Sound cues",
                          isOn: Binding(get: { preferences.soundCues }, set: { model.setSoundCues($0) }))
                    .disabled(!model.canChangeSettings)
            }
            SettingsRow(title: "Open at login", showsDivider: showsLoginIssue) {
                AppToggle(label: "Open at login",
                          isOn: Binding(get: { model.launchAtLogin.isOn }, set: { model.setLaunchAtLogin($0) }))
                    .disabled(!model.canChangeSettings)
            }
            if showsLoginIssue {
                StatusRow(tone: model.launchAtLoginError == nil ? .attention : .problem,
                          symbol: "exclamationmark.circle.fill",
                          title: model.launchAtLoginError == nil ? "Needs approval in Login Items" : "Login item problem",
                          detail: model.launchAtLoginError ?? "") {
                    Button("Open Login Items") { model.openLoginItemsSettings() }
                        .buttonStyle(AppButtonStyle(kind: .secondary, showsArrow: true, small: true))
                }
            }
        }
    }
}
