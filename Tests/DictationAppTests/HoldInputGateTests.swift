import XCTest
@testable import GPTVoice

final class HoldInputGateTests: XCTestCase {
    func testSecureInputAndSecurityAgentBypassTheHoldListener() {
        XCTAssertTrue(HoldInputGate.shouldBypass(secureInput: true, frontmostBundleID: "com.apple.finder"))
        XCTAssertTrue(HoldInputGate.shouldBypass(secureInput: false, frontmostBundleID: "com.apple.SecurityAgent"))
        XCTAssertTrue(HoldInputGate.shouldBypass(secureInput: false, frontmostBundleID: "com.apple.authorizationhost"))
        XCTAssertFalse(HoldInputGate.shouldBypass(secureInput: false, frontmostBundleID: "com.apple.Notes"))
        XCTAssertFalse(HoldInputGate.shouldBypass(secureInput: false, frontmostBundleID: nil))
    }
}
