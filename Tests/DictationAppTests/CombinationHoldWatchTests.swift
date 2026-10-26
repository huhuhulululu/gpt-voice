import XCTest
@testable import GPTVoice

final class CombinationHoldWatchTests: XCTestCase {
    func testAKeyThatIsAlreadyUpAfterTheGraceIsATap() {
        XCTAssertEqual(CombinationHoldWatch.afterGrace(keyStillDown: false), .treatAsTap)
    }

    func testAKeyThatIsStillDownAfterTheGraceIsAHold() {
        XCTAssertEqual(CombinationHoldWatch.afterGrace(keyStillDown: true), .beginHold)
    }

    func testReleaseAfterAHoldFinishesRecording() {
        XCTAssertEqual(CombinationHoldWatch.whileHolding(keyStillDown: true), .ignore)
        XCTAssertEqual(CombinationHoldWatch.whileHolding(keyStillDown: false), .finishHold)
    }
}
