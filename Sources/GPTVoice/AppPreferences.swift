import DictationCore
import Foundation

/// User preferences. Stores only settings and onboarding state.
/// Never stores credentials, audio, or transcripts. API keys use SecretStore.
@MainActor
final class AppPreferences: ObservableObject {
    private enum Key {
        static let hotkey = "hotkey"
        static let automaticPaste = "automaticPaste"
        static let soundCues = "soundCues"
        static let hapticCues = "hapticCues"
        static let onboardingCompleted = "onboardingCompleted"
        static let theme = "theme"
        static let accent = "accent"
        static let overlayPlacement = "overlayPlacement"
        static let manualPasteHelpDismissed = "manualPasteHelpDismissed"
        static let transcriptionProvider = "transcriptionProvider"
        static let openAIBaseURL = "openAIBaseURL"
        static let openAIModel = "openAIModel"
        static let transcriptionLanguage = "transcriptionLanguage"
        static let deterministicCleanup = "deterministicCleanup"
        static let vocabularyWords = "vocabularyWords"
        static let vocabularyReplacements = "vocabularyReplacements"
        static let filterWords = "filterWords"
        static let chatCleanup = "chatCleanup"
        static let chatCleanupModel = "chatCleanupModel"
        static let chatCleanupBaseURL = "chatCleanupBaseURL"
        static let chineseScript = "chineseScript"
    }

    @Published var overlayPlacement: OverlayPlacement {
        didSet { defaults.set(overlayPlacement.rawValue, forKey: Key.overlayPlacement) }
    }

    @Published var manualPasteHelpDismissed: Bool {
        didSet { defaults.set(manualPasteHelpDismissed, forKey: Key.manualPasteHelpDismissed) }
    }

    @Published var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Key.theme) }
    }

    @Published var accent: AccentChoice {
        didSet { defaults.set(accent.rawValue, forKey: Key.accent) }
    }

    private let defaults: UserDefaults

    @Published var hotkey: HotkeySpec {
        didSet {
            guard let data = try? JSONEncoder().encode(hotkey) else { return }
            defaults.set(data, forKey: Key.hotkey)
        }
    }

    @Published var automaticPaste: Bool {
        didSet { defaults.set(automaticPaste, forKey: Key.automaticPaste) }
    }

    @Published var soundCues: Bool {
        didSet { defaults.set(soundCues, forKey: Key.soundCues) }
    }

    @Published var hapticCues: Bool {
        didSet { defaults.set(hapticCues, forKey: Key.hapticCues) }
    }

    @Published var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Key.onboardingCompleted) }
    }

    @Published var transcriptionProvider: TranscriptionProvider {
        didSet { defaults.set(transcriptionProvider.rawValue, forKey: Key.transcriptionProvider) }
    }

    @Published var openAIBaseURL: String {
        didSet { defaults.set(openAIBaseURL, forKey: Key.openAIBaseURL) }
    }

    @Published var openAIModel: String {
        didSet { defaults.set(openAIModel, forKey: Key.openAIModel) }
    }

    @Published var transcriptionLanguage: String {
        didSet { defaults.set(transcriptionLanguage, forKey: Key.transcriptionLanguage) }
    }

    @Published var deterministicCleanup: Bool {
        didSet { defaults.set(deterministicCleanup, forKey: Key.deterministicCleanup) }
    }

    /// Legacy comma list. Read once to seed `lexicon.json`, then left untouched for downgrades.
    @Published var vocabularyWords: String {
        didSet { defaults.set(vocabularyWords, forKey: Key.vocabularyWords) }
    }

    /// Legacy `mishear => correct` lines. Read once to seed `lexicon.json`.
    @Published var vocabularyReplacements: String {
        didSet { defaults.set(vocabularyReplacements, forKey: Key.vocabularyReplacements) }
    }

    @Published var filterWords: String {
        didSet { defaults.set(filterWords, forKey: Key.filterWords) }
    }

    @Published var chatCleanup: Bool {
        didSet { defaults.set(chatCleanup, forKey: Key.chatCleanup) }
    }

    @Published var chatCleanupModel: String {
        didSet { defaults.set(chatCleanupModel, forKey: Key.chatCleanupModel) }
    }

    @Published var chatCleanupBaseURL: String {
        didSet { defaults.set(chatCleanupBaseURL, forKey: Key.chatCleanupBaseURL) }
    }

    @Published var chineseScript: ChineseScript {
        didSet { defaults.set(chineseScript.rawValue, forKey: Key.chineseScript) }
    }

    var openAIEndpoint: OpenAICompatibleEndpoint {
        OpenAICompatibleEndpoint(baseURL: openAIBaseURL, model: openAIModel, language: transcriptionLanguage)
    }

    var extraFilterWords: [String] { Vocabulary.parseWordList(filterWords) }
    var transcriptsInChinese: Bool { ChineseScript.isChinese(transcriptionLanguage) }
    /// Script conversion applies only when the language hint is Chinese.
    var effectiveChineseScript: ChineseScript { transcriptsInChinese ? chineseScript : .unchanged }

    /// No default server or model: chat cleanup does nothing until the user names both.
    nonisolated static let defaultChatCleanupBaseURL = ""
    nonisolated static let defaultChatCleanupModel = ""

    var chatCleanupEndpoint: String { chatCleanupBaseURL.trimmingCharacters(in: .whitespacesAndNewlines) }
    var chatCleanupModelID: String { chatCleanupModel.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// URL and model are set. The key is checked separately, at dictation time.
    var chatCleanupIsConfigured: Bool { !chatCleanupEndpoint.isEmpty && !chatCleanupModelID.isEmpty }

    var usesOpenAICompatible: Bool { transcriptionProvider == .openAICompatible }

    /// Short Home / Privacy label for the configured host. Never includes the key or path.
    var transcriptionHostTitle: String {
        let host = URL(string: openAIBaseURL)?.host?.lowercased() ?? ""
        if host.contains("groq.com") { return "Groq" }
        if host.contains("openai.com") { return "OpenAI" }
        if host.contains("localhost") || host.contains("127.0.0.1") { return "Local server" }
        return "OpenAI-compatible server"
    }

    func openAICompatibleIsReady(hasAPIKey: Bool) -> Bool {
        guard (try? OpenAICompatibleURL.transcriptions(from: openAIBaseURL)) != nil else { return false }
        if OpenAICompatibleURL.isLocalHost(openAIBaseURL) { return true }
        return hasAPIKey
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.automaticPaste: true,
            Key.soundCues: false,
            Key.hapticCues: false,
            Key.onboardingCompleted: false,
            Key.transcriptionProvider: TranscriptionProvider.codex.rawValue,
            Key.openAIBaseURL: "https://api.openai.com/v1",
            Key.openAIModel: "whisper-1",
            Key.transcriptionLanguage: "",
            Key.deterministicCleanup: true,
            Key.vocabularyWords: "",
            Key.vocabularyReplacements: "",
            Key.filterWords: "",
            Key.chatCleanup: false,
            Key.chatCleanupModel: Self.defaultChatCleanupModel,
            Key.chatCleanupBaseURL: Self.defaultChatCleanupBaseURL
        ])
        let stored = defaults.data(forKey: Key.hotkey).flatMap { try? JSONDecoder().decode(HotkeySpec.self, from: $0) }
        hotkey = stored.flatMap { $0.isValid ? $0 : nil } ?? .default
        automaticPaste = defaults.bool(forKey: Key.automaticPaste)
        soundCues = defaults.bool(forKey: Key.soundCues)
        hapticCues = defaults.bool(forKey: Key.hapticCues)
        onboardingCompleted = defaults.bool(forKey: Key.onboardingCompleted)
        theme = defaults.string(forKey: Key.theme).flatMap(AppTheme.init(rawValue:)) ?? .system
        let storedAccent = defaults.string(forKey: Key.accent)
        let resolvedAccent = AccentChoice(storedValue: storedAccent)
        accent = resolvedAccent
        if let storedAccent, storedAccent != resolvedAccent.rawValue {
            defaults.set(resolvedAccent.rawValue, forKey: Key.accent)
        }
        overlayPlacement = defaults.string(forKey: Key.overlayPlacement)
            .flatMap(OverlayPlacement.init(rawValue:)) ?? .bottom
        manualPasteHelpDismissed = defaults.bool(forKey: Key.manualPasteHelpDismissed)
        transcriptionProvider = defaults.string(forKey: Key.transcriptionProvider)
            .flatMap(TranscriptionProvider.init(rawValue:)) ?? .codex
        openAIBaseURL = defaults.string(forKey: Key.openAIBaseURL) ?? "https://api.openai.com/v1"
        openAIModel = defaults.string(forKey: Key.openAIModel) ?? "whisper-1"
        transcriptionLanguage = defaults.string(forKey: Key.transcriptionLanguage) ?? ""
        deterministicCleanup = defaults.bool(forKey: Key.deterministicCleanup)
        vocabularyWords = defaults.string(forKey: Key.vocabularyWords) ?? ""
        vocabularyReplacements = defaults.string(forKey: Key.vocabularyReplacements) ?? ""
        filterWords = defaults.string(forKey: Key.filterWords) ?? ""
        chatCleanup = defaults.bool(forKey: Key.chatCleanup)
        chatCleanupModel = defaults.string(forKey: Key.chatCleanupModel) ?? Self.defaultChatCleanupModel
        chatCleanupBaseURL = defaults.string(forKey: Key.chatCleanupBaseURL) ?? Self.defaultChatCleanupBaseURL
        chineseScript = defaults.string(forKey: Key.chineseScript).flatMap(ChineseScript.init(rawValue:)) ?? .simplified
    }
}
