import Foundation

enum SettingsPage: String, CaseIterable, Identifiable {
    case home
    case history
    case shortcuts
    case preferences
    case appearance
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .history: return "History"
        case .shortcuts: return "Shortcut"
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
        case .preferences: return "doc.on.clipboard"
        case .appearance: return "circle.lefthalf.filled"
        case .privacy: return "hand.raised"
        }
    }

    /// A subtitle only where the title alone does not explain the page.
    /// Shortcut uses the live hotkey instruction from SettingsView instead.
    var intro: String? {
        switch self {
        case .preferences: return "Automatic paste, sound cues, and login."
        case .privacy: return "Microphone, Accessibility, Input Monitoring, and what this app stores."
        case .home, .history, .shortcuts, .appearance: return nil
        }
    }
}
