import SwiftUI

/// Home: each state shown once with its action, then the current shortcut and one line of instruction.
struct HomePage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: AppPreferences
    let goTo: (SettingsPage) -> Void

    init(model: AppModel, goTo: @escaping (SettingsPage) -> Void) {
        self.model = model
        self.preferences = model.preferences
        self.goTo = goTo
    }

    private var showsInputMonitoring: Bool {
        model.hotkeyNeedsInputMonitoring || preferences.hotkey.isModifierHold
    }

    var body: some View {
        let ready = model.missingRequirements.isEmpty
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(footnote: ready
                ? preferences.hotkey.usageInstruction
                : "Dictation works once the items marked here are fixed.") {
                transcriptionStatus
                    .disabled(!model.canChangeSettings)
                RowDivider()
                MicrophoneCard(model: model, prominent: false)
                RowDivider()
                AccessibilityCard(model: model, onAdjustPaste: { goTo(.preferences) })
                if showsInputMonitoring {
                    RowDivider()
                    InputMonitoringCard(model: model)
                }
                RowDivider()
                SettingsRow(title: "Shortcut",
                            detail: model.hotkeyError == nil ? preferences.hotkey.usageInstruction : nil,
                            showsDivider: model.hotkeyError != nil) {
                    HStack(spacing: 8) {
                        KeycapsView(spec: preferences.hotkey)
                        Button("Change") { goTo(.shortcuts) }
                            .buttonStyle(AppButtonStyle(kind: .quiet, small: true))
                    }
                }
                if let error = model.hotkeyError {
                    StatusRow(tone: .problem, symbol: "exclamationmark.triangle.fill",
                              title: "Shortcut needs a fix", detail: error) {
                        if model.hotkeyBlockedBySystem {
                            Button("Keyboard settings") { model.openKeyboardShortcutsSettings() }
                                .buttonStyle(AppButtonStyle(kind: .secondary, showsArrow: true, small: true))
                        } else if model.hotkeyNeedsInputMonitoring {
                            Button("Input Monitoring settings") { model.openInputMonitoringSettings() }
                                .buttonStyle(AppButtonStyle(kind: .secondary, showsArrow: true, small: true))
                        }
                        Button("Change shortcut") { goTo(.shortcuts) }
                            .buttonStyle(AppButtonStyle(kind: .quiet, small: true))
                    }
                }
            }

            InfoDisclosure(label: "How dictation works", text: howDictationWorks)
        }
    }

    @ViewBuilder private var transcriptionStatus: some View {
        if preferences.usesOpenAICompatible {
            let ready = model.transcriptionIsReady
            StatusRow(tone: ready ? .good : .attention,
                      symbol: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                      title: ready ? "OpenAI-compatible server" : "Transcription server needed",
                      detail: ready
                        ? "Audio goes to \(preferences.openAIModel) at your configured URL."
                        : "Add a base URL and API key in Transcription.") {
                Button("Configure") { goTo(.transcription) }
                    .buttonStyle(AppButtonStyle(kind: .quiet, small: true))
            }
        } else {
            ConnectionPanel(model: model, prominentSignIn: false)
        }
    }

    private var howDictationWorks: String {
        let start = preferences.hotkey.isModifierHold
            ? "Click where you want the text. Hold \(preferences.hotkey.displayLabel) and speak. Release to finish."
            : "Click where you want the text. Hold \(preferences.hotkey.displayLabel) and speak, then release. A short tap still starts; press again to finish."
        return start + " With automatic paste, the text goes where you clicked. Otherwise it is copied and you press ⌘V."
    }
}
