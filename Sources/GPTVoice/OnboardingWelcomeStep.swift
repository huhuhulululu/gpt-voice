import DictationCore
import SwiftUI

/// Welcome in three zones: what it does, a small demonstration with the real keys and bar, and the provider row.
struct OnboardingWelcomeStep: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: AppPreferences
    @State private var apiKeyDraft = ""

    init(model: AppModel) {
        self.model = model
        self.preferences = model.preferences
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            OnboardingHeader(title: "Dictate into any app",
                             summary: "Hold your shortcut, speak, and let go to paste.")

            HStack(spacing: 14) {
                KeycapsView(spec: preferences.hotkey)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                DictationOverlayView(state: .recording(elapsed: 4, level: 0.5), actions: .preview)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sample: hold \(preferences.hotkey.accessibilityLabel) and the recording bar appears.")

            VStack(alignment: .leading, spacing: 8) {
                SettingsGroup {
                    SettingsRow(title: "Provider") {
                        AppSegmented(label: "Transcription provider", options: TranscriptionProvider.allCases,
                                     title: \.title,
                                     selection: Binding(get: { preferences.transcriptionProvider },
                                                        set: { model.setTranscriptionProvider($0) }))
                    }
                    if preferences.usesOpenAICompatible {
                        SettingsRow(title: "Base URL") {
                            AppTextField(label: "Base URL", text: $preferences.openAIBaseURL,
                                         placeholder: "https://api.groq.com/openai/v1")
                        }
                        SettingsRow(title: "API key",
                                    detail: model.openAIKeyPresent ? "A key is saved on this Mac." : nil) {
                            AppTextField(label: "API key", text: $apiKeyDraft, placeholder: "gsk-… or sk-…",
                                         secure: true)
                        }
                        SettingsRow(title: "Save & Test", showsDivider: false) {
                            HStack(spacing: 8) {
                                Button("Use Groq") { model.applyGroqPreset() }
                                    .buttonStyle(AppButtonStyle(kind: .quiet, small: true))
                                Button(model.isTestingConnection ? "Testing…" : "Save & Test") {
                                    model.testOpenAIConnection(apiKeyDraft: apiKeyDraft)
                                }
                                .buttonStyle(AppButtonStyle(kind: .secondary,
                                                            isLoading: model.isTestingConnection, small: true))
                                .disabled(model.isTestingConnection)
                            }
                        }
                    } else {
                        ConnectionPanel(model: model, prominentSignIn: true)
                    }
                }
                Text(preferences.usesOpenAICompatible
                     ? "Audio is sent to your server. Groq uses https://api.groq.com/openai/v1 and whisper-large-v3. Set language to zh for Chinese."
                     : "Audio is sent to ChatGPT for transcription.")
                    .font(AppType.detail)
                    .foregroundStyle(.secondary)
                if let result = model.connectionTest, preferences.usesOpenAICompatible {
                    Text(result.message)
                        .font(AppType.detail)
                        .foregroundStyle(result.ok ? AppPalette.success : AppPalette.problem)
                }
                InfoDisclosure(label: "Storage and account",
                               text: preferences.usesOpenAICompatible
                                ? "Recordings are temporary files. Transcripts are saved on this Mac, and you can remove them in History. The API key stays in the Keychain. This app makes no copy of your audio after a successful transcription."
                                : "Recordings are temporary files. Transcripts are saved on this Mac, and you can remove them in History. Sign-in is shared with Codex CLI, and this app makes no copy of your credentials.")
            }
        }
    }
}
