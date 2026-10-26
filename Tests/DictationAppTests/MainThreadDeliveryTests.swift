import XCTest
@testable import GPTVoice

final class MainThreadDeliveryTests: XCTestCase {
    @MainActor
    func testMainThreadWorkRunsBeforeReturning() {
        var ran = false
        MainThreadDelivery.run {
            ran = true
        }
        XCTAssertTrue(ran, "Hold-to-talk delivery must not hop off the current main-thread event.")
    }

    func testOffMainThreadWorkRunsOnTheMainActor() {
        let ran = expectation(description: "delivered on main")
        DispatchQueue.global(qos: .userInitiated).async {
            MainThreadDelivery.run {
                XCTAssertTrue(Thread.isMainThread)
                ran.fulfill()
            }
        }
        wait(for: [ran], timeout: 1)
    }
}
