import DictationCore
import SwiftUI

/// Provider, OpenAI-compatible server, local cleanup, and optional chat polish.
struct TranscriptionPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: AppPreferences
    @State private var apiKeyDraft = ""

    init(model: AppModel) {
        self.model = model
        self.preferences = model.preferences
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup {
                SettingsRow(title: "Provider",
                            detail: preferences.usesOpenAICompatible
                                ? "Sends audio to Groq, OpenAI, or any /v1/audio/transcriptions server."
                                : "Uses your Codex CLI ChatGPT sign-in. Default.") {
                    AppSegmented(label: "Transcription provider", options: TranscriptionProvider.allCases,
                                 title: \.title,
                                 selection: Binding(get: { preferences.transcriptionProvider },
                                                    set: { model.setTranscriptionProvider($0) }))
                    .disabled(!model.canChangeSettings)
                }
            }

            if preferences.usesOpenAICompatible {
                openAIGroup
            } else {
                SettingsGroup {
                    ConnectionPanel(model: model, prominentSignIn: false)
                        .disabled(!model.canChangeSettings)
                }
            }

            cleanupGroup
            vocabularyGroup
            chatGroup
        }
        .onAppear { apiKeyDraft = "" }
    }

    private var openAIGroup: some View {
        SettingsGroup(footnote: "API keys stay in the Keychain on this Mac. Local servers can omit a key. Groq needs /openai/v1, not /v1.") {
            SettingsRow(title: "Base URL",
                        detail: "Groq: https://api.groq.com/openai/v1 · OpenAI: https://api.openai.com/v1") {
                AppTextField(label: "Base URL", text: $preferences.openAIBaseURL,
                             placeholder: "https://api.groq.com/openai/v1")
                    .disabled(!model.canChangeSettings)
            }
            SettingsRow(title: "Model",
                        detail: "Groq: whisper-large-v3. OpenAI: whisper-1.") {
                AppTextField(label: "Model", text: $preferences.openAIModel, placeholder: "whisper-large-v3")
                    .disabled(!model.canChangeSettings)
            }
            SettingsRow(title: "Language hint",
                        detail: "zh improves Chinese. Leave blank only if you switch languages often.") {
                VStack(alignment: .trailing, spacing: 8) {
                    AppTextField(label: "Language hint", text: $preferences.transcriptionLanguage, placeholder: "zh")
                        .disabled(!model.canChangeSettings)
                    HStack(spacing: 6) {
                        languageChip("zh")
                        languageChip("en")
                        languageChip("Auto", value: "")
                    }
                }
            }
            SettingsRow(title: "API key",
                        detail: model.openAIKeyPresent
                            ? "A key is saved on this Mac. Enter a new one to replace it."
                            : "Required for Groq and other hosted APIs. Optional for localhost.") {
                AppTextField(label: "API key", text: $apiKeyDraft, placeholder: "gsk-… or sk-…", secure: true)
                    .disabled(!model.canChangeSettings)
            }
            SettingsRow(title: "Save & Test", showsDivider: model.connectionTest != nil) {
                HStack(spacing: 8) {
                    Button("Use Groq") { model.applyGroqPreset() }
                        .buttonStyle(AppButtonStyle(kind: .quiet, small: true))
                        .disabled(!model.canChangeSettings)
                    Button(model.isTestingConnection ? "Testing…" : "Save & Test") {
                        model.testOpenAIConnection(apiKeyDraft: apiKeyDraft)
                    }
                    .buttonStyle(AppButtonStyle(kind: .secondary, isLoading: model.isTestingConnection, small: true))
                    .disabled(!model.canChangeSettings || model.isTestingConnection)
                    if model.openAIKeyPresent {
                        Button("Clear key") { model.clearOpenAIKey(); apiKeyDraft = "" }
                            .buttonStyle(AppButtonStyle(kind: .quiet, small: true))
                            .disabled(!model.canChangeSettings)
                    }
                }
            }
            if let result = model.connectionTest {
                StatusRow(tone: result.ok ? .good : .problem,
                          symbol: result.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                          title: result.ok ? "Ready to dictate" : "Connection failed",
                          detail: result.message) { EmptyView() }
            }
        }
    }

    private var cleanupGroup: some View {
        SettingsGroup {
            SettingsRow(title: "Clean up transcript",
                        detail: "Local rules: strip fillers, trim Whisper sign-offs, and tidy spaces. Helps Chinese and English.") {
                AppToggle(label: "Clean up transcript",
                          isOn: $preferences.deterministicCleanup)
                    .disabled(!model.canChangeSettings)
            }
            SettingsRow(title: "Extra filter words",
                        detail: "Optional. Comma-separated. Built-in fillers such as um and 嗯 stay on when cleanup is enabled.",
                        showsDivider: false) {
                AppTextField(label: "Extra filter words", text: $preferences.filterWords, placeholder: "kinda, 那个")
                    .disabled(!model.canChangeSettings)
            }
        }
    }

    private var vocabularyGroup: some View {
        SettingsGroup(footnote: "Custom words go into the transcription prompt as a glossary sentence. Replacements run on this Mac after STT.") {
            SettingsRow(title: "Custom words",
                        detail: "Names and terms to prefer. Useful for Chinese proper nouns.") {
                AppTextField(label: "Custom words", text: $preferences.vocabularyWords,
                             placeholder: "Goice, 专有名词")
                    .disabled(!model.canChangeSettings)
            }
            SettingsRow(title: "Replacements",
                        detail: "One per line: mishear => correct",
                        showsDivider: false) {
                AppTextField(label: "Replacements", text: $preferences.vocabularyReplacements,
                             placeholder: "go ice => Goice")
                    .disabled(!model.canChangeSettings)
            }
        }
    }

    private var chatGroup: some View {
        SettingsGroup(footnote: "Off by default. Uses an OpenAI-compatible chat endpoint. A failure keeps the local cleanup.") {
            SettingsRow(title: "LLM cleanup",
                        detail: "Sends the transcript to a chat model. Not used for speech-to-text.") {
                AppToggle(label: "LLM cleanup", isOn: $preferences.chatCleanup)
                    .disabled(!model.canChangeSettings)
            }
            if preferences.chatCleanup {
                SettingsRow(title: "Chat model") {
                    AppTextField(label: "Chat model", text: $preferences.chatCleanupModel,
                                 placeholder: "gpt-4o-mini")
                        .disabled(!model.canChangeSettings)
                }
                SettingsRow(title: "Chat base URL",
                            detail: "Leave blank to reuse the transcription server URL.",
                            showsDivider: false) {
                    AppTextField(label: "Chat base URL", text: $preferences.chatCleanupBaseURL,
                                 placeholder: preferences.openAIBaseURL)
                        .disabled(!model.canChangeSettings)
                }
            }
        }
    }

    private func languageChip(_ title: String, value: String? = nil) -> some View {
        let code = value ?? title
        let selected = preferences.transcriptionLanguage == code
        return Button(title) {
            guard model.canChangeSettings else { return }
            preferences.transcriptionLanguage = code
        }
        .buttonStyle(AppButtonStyle(kind: selected ? .secondary : .quiet, small: true))
        .disabled(!model.canChangeSettings)
        .accessibilityLabel("Language \(title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
