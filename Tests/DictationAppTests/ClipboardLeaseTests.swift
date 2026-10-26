import XCTest
@testable import GPTVoice

final class ClipboardLeaseTests: XCTestCase {
    func testAutoPasteRestoresWhenTheLeaseIsUnchanged() {
        XCTAssertTrue(ClipboardLease.shouldRestore(ownedChange: 4, currentChange: 4,
                                                   written: "hello", currentString: "hello"))
    }

    func testAutoPasteRestoresWhenAHelperRewritesTheSameTranscript() {
        XCTAssertTrue(ClipboardLease.shouldRestore(ownedChange: 4, currentChange: 6,
                                                   written: "hello", currentString: "hello"))
    }

    func testAutoPastePreservesANewerClipboard() {
        XCTAssertFalse(ClipboardLease.shouldRestore(ownedChange: 4, currentChange: 6,
                                                    written: "hello", currentString: "user copied this"))
    }

    func testAutoPasteDoesNotRestoreAnUnrelatedEmptyClipboard() {
        XCTAssertFalse(ClipboardLease.shouldRestore(ownedChange: 4, currentChange: 7,
                                                    written: "hello", currentString: nil))
    }
}
