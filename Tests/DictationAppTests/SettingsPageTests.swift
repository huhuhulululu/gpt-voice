import XCTest
@testable import GPTVoice

final class SettingsPageTests: XCTestCase {
    func testSidebarNamesPasteAndKeepsShortcutNearby() {
        XCTAssertEqual(SettingsPage.allCases.map(\.title), [
            "Home", "History", "Shortcut", "Transcription", "Paste & behavior", "Appearance", "Privacy"
        ])
        XCTAssertEqual(SettingsPage.preferences.intro, "Automatic paste, sound, haptics, and login.")
        XCTAssertEqual(SettingsPage.transcription.intro,
                       "Codex, Groq, or any OpenAI-compatible server. Cleanup stays on this Mac.")
        XCTAssertEqual(SettingsPage.history.intro,
                       "Saved on this Mac. Pasted rows name the app; copied rows say why paste was skipped.")
        XCTAssertEqual(SettingsPage.appearance.intro, "Theme, accent, and where the recording bar sits.")
        XCTAssertEqual(SettingsPage.privacy.intro,
                       "Microphone, Accessibility, Input Monitoring, and what this app stores.")
        XCTAssertNil(SettingsPage.shortcuts.intro)
        XCTAssertNil(SettingsPage.home.intro)
    }
}
