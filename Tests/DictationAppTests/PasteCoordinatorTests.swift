import AppKit
import XCTest
@testable import GPTVoice

@MainActor
final class PasteCoordinatorTests: XCTestCase {
    func testAutomaticPasteRestoresThePreviousClipboard() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("keep me", forType: .string)
        let coordinator = PasteCoordinator(pasteboard: pasteboard, environment: .test(pasteboard: pasteboard, insert: false, inject: true))

        coordinator.beginSession(target: .fixture(pid: 99))
        let outcome = await coordinator.deliver(text: "dictated text", automaticPaste: true)

        XCTAssertEqual(outcome, .pasted(appName: "Notes"))
        XCTAssertEqual(pasteboard.string(forType: .string), "keep me")
        XCTAssertFalse(coordinator.isLeasePending)
    }

    func testAutomaticPasteRestoresAfterAHelperRewritesTheSameTranscript() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("keep me", forType: .string)
        let coordinator = PasteCoordinator(pasteboard: pasteboard, environment: .test(pasteboard: pasteboard, insert: false, inject: { board in
            board.clearContents()
            board.setString("dictated text", forType: .string)
            return true
        }))

        coordinator.beginSession(target: .fixture(pid: 99))
        let outcome = await coordinator.deliver(text: "dictated text", automaticPaste: true)

        XCTAssertEqual(outcome, .pasted(appName: "Notes"))
        XCTAssertEqual(pasteboard.string(forType: .string), "keep me")
    }

    func testAutomaticInsertDoesNotTouchTheClipboard() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("keep me", forType: .string)
        let coordinator = PasteCoordinator(pasteboard: pasteboard, environment: .test(pasteboard: pasteboard, insert: true, inject: false))

        coordinator.beginSession(target: .fixture(pid: 99))
        let outcome = await coordinator.deliver(text: "dictated text", automaticPaste: true)

        XCTAssertEqual(outcome, .pasted(appName: "Notes"))
        XCTAssertEqual(pasteboard.string(forType: .string), "keep me")
    }

    func testManualPasteKeepsTheTranscriptForCommandV() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("keep me", forType: .string)
        let coordinator = PasteCoordinator(pasteboard: pasteboard, environment: .test(pasteboard: pasteboard, insert: false, inject: false))

        coordinator.beginSession(target: .fixture(pid: 99))
        let outcome = await coordinator.deliver(text: "dictated text", automaticPaste: false)

        XCTAssertEqual(outcome, .copied(.automaticPasteOff))
        XCTAssertEqual(pasteboard.string(forType: .string), "dictated text")
    }

    func testANewerClipboardIsLeftAlone() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("keep me", forType: .string)
        let coordinator = PasteCoordinator(pasteboard: pasteboard, environment: .test(pasteboard: pasteboard, insert: false, inject: true))

        coordinator.beginSession(target: .fixture(pid: 99))
        pasteboard.clearContents()
        pasteboard.setString("user copied this", forType: .string)
        let outcome = await coordinator.deliver(text: "dictated text", automaticPaste: true)

        XCTAssertEqual(outcome, .preservedNewerClipboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "user copied this")
    }

    func testAccessibilityFailureKeepsTheTranscriptForManualPaste() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("keep me", forType: .string)
        var environment = PasteCoordinator.Environment.test(pasteboard: pasteboard, insert: false, inject: false)
        environment.isAccessibilityTrusted = { false }
        let coordinator = PasteCoordinator(pasteboard: pasteboard, environment: environment)

        coordinator.beginSession(target: .fixture(pid: 99))
        let outcome = await coordinator.deliver(text: "dictated text", automaticPaste: true)

        XCTAssertEqual(outcome, .copied(.accessibilityMissing))
        XCTAssertEqual(pasteboard.string(forType: .string), "dictated text")
    }

    func testTargetChangeKeepsTheTranscriptForManualPaste() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("keep me", forType: .string)
        var environment = PasteCoordinator.Environment.test(pasteboard: pasteboard, insert: false, inject: false)
        environment.isStillFrontmost = { _ in false }
        let coordinator = PasteCoordinator(pasteboard: pasteboard, environment: environment)

        coordinator.beginSession(target: .fixture(pid: 99))
        let outcome = await coordinator.deliver(text: "dictated text", automaticPaste: true)

        XCTAssertEqual(outcome, .copied(.targetChanged))
        XCTAssertEqual(pasteboard.string(forType: .string), "dictated text")
    }

    func testCancelBeforeDeliveryLeavesTheClipboardAlone() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("keep me", forType: .string)
        let coordinator = PasteCoordinator(pasteboard: pasteboard, environment: .test(pasteboard: pasteboard, insert: false, inject: true))

        coordinator.beginSession(target: .fixture(pid: 99))
        coordinator.endSession()

        XCTAssertEqual(pasteboard.string(forType: .string), "keep me")
        XCTAssertFalse(coordinator.isLeasePending)
    }
}

private extension PasteCoordinator.Environment {
    static func test(pasteboard: NSPasteboard, insert: Bool, inject: Bool) -> Self {
        test(pasteboard: pasteboard, insert: insert, inject: { _ in inject })
    }

    static func test(pasteboard: NSPasteboard, insert: Bool, inject: @escaping (NSPasteboard) -> Bool) -> Self {
        var environment = PasteCoordinator.Environment.live
        environment.restoreDelay = 0
        environment.isAccessibilityTrusted = { true }
        environment.captureFrontmost = { .fixture(pid: 99) }
        environment.isStillFrontmost = { _ in true }
        environment.insertSelectedText = { _, _ in insert }
        environment.injectPaste = { inject(pasteboard) }
        return environment
    }
}

private extension PasteTarget {
    static func fixture(pid: pid_t) -> PasteTarget {
        PasteTarget(processID: pid, appName: "Notes", focusedElement: nil, focusedWindow: nil)
    }
}
