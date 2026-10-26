import XCTest
@testable import GPTVoice

final class PasteTargetTests: XCTestCase {
    func testSameFrontmostAppStillAcceptsDelivery() {
        XCTAssertTrue(PasteTarget.deliveryStillValid(capturedPID: 40, frontmostPID: 40))
    }

    func testADifferentFrontmostAppDoesNotAcceptDelivery() {
        XCTAssertFalse(PasteTarget.deliveryStillValid(capturedPID: 40, frontmostPID: 41))
        XCTAssertFalse(PasteTarget.deliveryStillValid(capturedPID: 40, frontmostPID: nil))
    }

    func testOwnAppFrontmostStillAllowsAutomaticDelivery() {
        XCTAssertTrue(PasteTarget.shouldAttemptAutomaticDelivery(capturedPID: 40, frontmostPID: 7, ownPID: 7))
        XCTAssertTrue(PasteTarget.shouldAttemptAutomaticDelivery(capturedPID: 40, frontmostPID: 40, ownPID: 7))
        XCTAssertTrue(PasteTarget.isOwnAppFrontmost(frontmostPID: 7, ownPID: 7))
    }

    func testADifferentThirdPartyAppDoesNotAllowAutomaticDelivery() {
        XCTAssertFalse(PasteTarget.shouldAttemptAutomaticDelivery(capturedPID: 40, frontmostPID: 41, ownPID: 7))
        XCTAssertFalse(PasteTarget.shouldAttemptAutomaticDelivery(capturedPID: 40, frontmostPID: nil, ownPID: 7))
        XCTAssertFalse(PasteTarget.isOwnAppFrontmost(frontmostPID: 41, ownPID: 7))
    }
}
