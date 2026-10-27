import XCTest
@testable import GPTVoice

@MainActor
final class AccentChoiceTests: XCTestCase {
    func testFiveColorwaysWithCoralVioletAsFactoryDefault() {
        XCTAssertEqual(AccentChoice.allCases, [.coralViolet, .softBlue, .sage, .amber, .graphite])
        XCTAssertEqual(AccentChoice.factoryDefault, .coralViolet)
        XCTAssertEqual(AccentChoice.allCases.map(\.chineseTitle), ["珊瑚紫", "雾蓝", "鼠尾草绿", "暖琥珀", "石墨灰"])
    }

    func testEarlierSevenAccentValuesMapToTheNearestColorway() {
        XCTAssertEqual(AccentChoice(storedValue: "rose"), .coralViolet)
        XCTAssertEqual(AccentChoice(storedValue: "violet"), .coralViolet)
        XCTAssertEqual(AccentChoice(storedValue: "green"), .sage)
        XCTAssertEqual(AccentChoice(storedValue: "teal"), .sage)
        XCTAssertEqual(AccentChoice(storedValue: "blue"), .softBlue)
        XCTAssertEqual(AccentChoice(storedValue: "amber"), .amber)
        XCTAssertEqual(AccentChoice(storedValue: "system"), .graphite)
    }

    func testCurrentValuesRoundTripAndUnknownValuesFallBack() {
        for choice in AccentChoice.allCases {
            XCTAssertEqual(AccentChoice(storedValue: choice.rawValue), choice)
        }
        XCTAssertEqual(AccentChoice(storedValue: nil), .coralViolet)
        XCTAssertEqual(AccentChoice(storedValue: "magenta"), .coralViolet)
    }

    func testFreshPreferencesStartOnCoralViolet() {
        let defaults = UserDefaults(suiteName: "goice-accent-fresh-\(UUID().uuidString)")!
        XCTAssertEqual(AppPreferences(defaults: defaults).accent, .coralViolet)
        XCTAssertNil(defaults.string(forKey: "accent"))
    }

    func testOldSavedAccentIsRewrittenOnceAndThenKept() {
        let defaults = UserDefaults(suiteName: "goice-accent-migrate-\(UUID().uuidString)")!
        defaults.set("teal", forKey: "accent")
        XCTAssertEqual(AppPreferences(defaults: defaults).accent, .sage)
        XCTAssertEqual(defaults.string(forKey: "accent"), "sage")

        let preferences = AppPreferences(defaults: defaults)
        XCTAssertEqual(preferences.accent, .sage)
        preferences.accent = .amber
        XCTAssertEqual(AppPreferences(defaults: defaults).accent, .amber)
    }

    func testEveryColorwayHasThreeStopRamps() {
        for choice in AccentChoice.allCases {
            for dark in [false, true] {
                XCTAssertEqual(choice.waveRamp(dark: dark).count, 3, "\(choice) wave")
                XCTAssertEqual(choice.fillRamp(dark: dark).count, 3, "\(choice) fill")
                XCTAssertEqual(choice.buttonRamp(dark: dark).count, 3, "\(choice) button")
            }
        }
    }

    func testMixBlendsEachChannel() {
        XCTAssertEqual(AppPalette.mix(0x000000, 0xFFFFFF, 0), 0x000000)
        XCTAssertEqual(AppPalette.mix(0x000000, 0xFFFFFF, 1), 0xFFFFFF)
        XCTAssertEqual(AppPalette.mix(0xFF0000, 0x0000FF, 0.5), 0x800080)
    }
}
