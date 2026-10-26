import Carbon.HIToolbox
import XCTest
@testable import GPTVoice

final class ModifierTapTrackerTests: XCTestCase {
    private let leftOption = UInt32(kVK_Option)

    func testAShortPressAndReleaseIsATap() {
        var tracker = ModifierTapTracker(keyCode: leftOption, maximumDuration: 1)
        XCTAssertFalse(tracker.consume(eventKeyCode: leftOption, modifierDown: true, otherModifierDown: false,
                                       timestamp: 10, cancelsTap: false))
        XCTAssertTrue(tracker.consume(eventKeyCode: leftOption, modifierDown: false, otherModifierDown: false,
                                      timestamp: 10.2, cancelsTap: false))
    }

    func testAHoldLongerThanTheLimitIsNotATap() {
        var tracker = ModifierTapTracker(keyCode: leftOption, maximumDuration: 1)
        XCTAssertFalse(tracker.consume(eventKeyCode: leftOption, modifierDown: true, otherModifierDown: false,
                                       timestamp: 10, cancelsTap: false))
        XCTAssertFalse(tracker.consume(eventKeyCode: leftOption, modifierDown: false, otherModifierDown: false,
                                       timestamp: 11.01, cancelsTap: false))
    }

    func testAnotherKeyOrMouseClickCancelsTheTap() {
        var tracker = ModifierTapTracker(keyCode: leftOption, maximumDuration: 1)
        XCTAssertFalse(tracker.consume(eventKeyCode: leftOption, modifierDown: true, otherModifierDown: false,
                                       timestamp: 1, cancelsTap: false))
        XCTAssertFalse(tracker.consume(eventKeyCode: nil, modifierDown: false, otherModifierDown: false,
                                       timestamp: 1.1, cancelsTap: true))
        XCTAssertFalse(tracker.consume(eventKeyCode: leftOption, modifierDown: false, otherModifierDown: false,
                                       timestamp: 1.2, cancelsTap: false))
    }

    func testAnotherModifierCancelsTheTap() {
        var tracker = ModifierTapTracker(keyCode: leftOption, maximumDuration: 1)
        XCTAssertFalse(tracker.consume(eventKeyCode: leftOption, modifierDown: true, otherModifierDown: false,
                                       timestamp: 1, cancelsTap: false))
        XCTAssertFalse(tracker.consume(eventKeyCode: UInt32(kVK_Shift), modifierDown: false, otherModifierDown: true,
                                       timestamp: 1.1, cancelsTap: false))
        XCTAssertFalse(tracker.consume(eventKeyCode: leftOption, modifierDown: false, otherModifierDown: false,
                                       timestamp: 1.2, cancelsTap: false))
    }

    func testTheOtherOptionKeyDoesNotCompleteALeftOptionTap() {
        var tracker = ModifierTapTracker(keyCode: leftOption, maximumDuration: 1)
        XCTAssertFalse(tracker.consume(eventKeyCode: UInt32(kVK_RightOption), modifierDown: true,
                                       otherModifierDown: false, timestamp: 1, cancelsTap: false))
        XCTAssertFalse(tracker.consume(eventKeyCode: UInt32(kVK_RightOption), modifierDown: false,
                                       otherModifierDown: false, timestamp: 1.1, cancelsTap: false))
    }

    func testReleaseWithoutAPressDoesNotFire() {
        var tracker = ModifierTapTracker(keyCode: leftOption, maximumDuration: 1)
        XCTAssertFalse(tracker.consume(eventKeyCode: leftOption, modifierDown: false, otherModifierDown: false,
                                       timestamp: 5, cancelsTap: false))
    }
}
