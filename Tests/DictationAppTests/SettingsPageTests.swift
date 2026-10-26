import XCTest
@testable import GPTVoice

final class SettingsPageTests: XCTestCase {
    func testSidebarNamesPasteAndKeepsShortcutNearby() {
        XCTAssertEqual(SettingsPage.allCases.map(\.title), [
            "Home", "History", "Shortcut", "Transcription", "Paste & behavior", "Appearance", "Privacy"
        ])
        XCTAssertEqual(SettingsPage.preferences.intro, "Automatic paste, sound cues, and login.")
        XCTAssertEqual(SettingsPage.transcription.intro, "Provider, cleanup, and vocabulary.")
        XCTAssertEqual(SettingsPage.privacy.intro,
                       "Microphone, Accessibility, Input Monitoring, and what this app stores.")
        XCTAssertNil(SettingsPage.shortcuts.intro)
    }
}
