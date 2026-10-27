import Foundation

enum SettingsPage: String, CaseIterable, Identifiable {
    case home
    case history
    case shortcuts
    case transcription
    case preferences
    case appearance
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .history: return "History"
        case .shortcuts: return "Shortcut"
        case .transcription: return "Transcription"
        case .preferences: return "Paste & behavior"
        case .appearance: return "Appearance"
        case .privacy: return "Privacy"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .history: return "clock.arrow.circlepath"
        case .shortcuts: return "command"
        case .transcription: return "waveform"
        case .preferences: return "doc.on.clipboard"
        case .appearance: return "circle.lefthalf.filled"
        case .privacy: return "hand.raised"
        }
    }

    /// A subtitle only where the title alone does not explain the page.
    /// Shortcut uses the live hotkey instruction from SettingsView instead.
    var intro: String? {
        switch self {
        case .history: return "Saved on this Mac. Pasted rows name the app; copied rows say why paste was skipped."
        case .preferences: return "Automatic paste, sound, haptics, and login."
        case .transcription: return "Codex, Groq, or any OpenAI-compatible server. Cleanup stays on this Mac."
        case .appearance: return "Theme, accent, and where the recording bar sits."
        case .privacy: return "Microphone, Accessibility, Input Monitoring, and what this app stores."
        case .home, .shortcuts: return nil
        }
    }
}
