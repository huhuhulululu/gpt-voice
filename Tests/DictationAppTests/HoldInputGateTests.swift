import XCTest
@testable import GPTVoice

final class HoldInputGateTests: XCTestCase {
    func testAuthAgentsBypassTheHoldListener() {
        XCTAssertTrue(HoldInputGate.shouldBypass(frontmostBundleID: "com.apple.SecurityAgent",
                                                 secureInputOwnerBundleID: nil))
        XCTAssertTrue(HoldInputGate.shouldBypass(frontmostBundleID: "com.apple.Notes",
                                                 secureInputOwnerBundleID: "com.apple.SecurityAgent"))
        XCTAssertTrue(HoldInputGate.shouldBypass(frontmostBundleID: "com.apple.authorizationhost",
                                                 secureInputOwnerBundleID: nil))
    }

    func testOtherSecureInputOwnersKeepLeftOptionWorking() {
        XCTAssertFalse(HoldInputGate.shouldBypass(frontmostBundleID: "com.apple.Terminal",
                                                  secureInputOwnerBundleID: "com.apple.Terminal"))
        XCTAssertFalse(HoldInputGate.shouldBypass(frontmostBundleID: "com.apple.Notes",
                                                  secureInputOwnerBundleID: "com.1password.1password"))
        XCTAssertFalse(HoldInputGate.shouldBypass(frontmostBundleID: nil, secureInputOwnerBundleID: nil))
    }
}
