import AppKit
import Combine
import DictationCore
import XCTest
@testable import GPTVoice

@MainActor
final class AppModelClipboardTests: XCTestCase {
    func testAutoPasteThroughTheModelRestoresTheClipboard() async throws {
        let fixture = Fixture(automaticPaste: true)
        defer { fixture.cleanup() }

        fixture.model.transcribeFile(URL(fileURLWithPath: "/auto-paste-restore.wav"))
        try await fixture.waitUntil { fixture.model.phase == .finished(.pasted(appName: "Notes")) }

        XCTAssertEqual(fixture.clipboard.string(forType: .string), "keep me")
        XCTAssertFalse(fixture.model.isPasteLeasePending)
    }

    func testManualPasteKeepsTheTranscriptOnTheClipboard() async throws {
        let fixture = Fixture(automaticPaste: false)
        defer { fixture.cleanup() }

        fixture.model.transcribeFile(URL(fileURLWithPath: "/manual-paste-keep.wav"))
        try await fixture.waitUntil { fixture.model.phase == .finished(.copied(.automaticPasteOff)) }

        XCTAssertEqual(fixture.clipboard.string(forType: .string), "Spoken line")
        XCTAssertEqual(fixture.model.phase.statusText, "Copied. Press ⌘V to paste.")
    }

    func testReleasingTheShortcutWhileTranscribingDoesNotCancelDelivery() async throws {
        let started = expectation(description: "Transcription started")
        let fixture = Fixture(automaticPaste: true) { _ in
            started.fulfill()
            try await Task.sleep(nanoseconds: 80_000_000)
            return "Spoken line"
        }
        defer { fixture.cleanup() }

        fixture.model.transcribeFile(URL(fileURLWithPath: "/release-during-transcribe.wav"))
        await fulfillment(of: [started], timeout: 2)
        fixture.model.receiveGlobalShortcutRelease()
        try await fixture.waitUntil { fixture.model.phase == .finished(.pasted(appName: "Notes")) }

        XCTAssertEqual(fixture.clipboard.string(forType: .string), "keep me")
    }

    func testCancelDuringTranscriptionLeavesTheClipboardAlone() async throws {
        let started = expectation(description: "Transcription started")
        let fixture = Fixture(automaticPaste: true) { _ in
            started.fulfill()
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return "Late text"
        }
        defer { fixture.cleanup() }

        fixture.model.transcribeFile(URL(fileURLWithPath: "/cancel-mid-transcription.wav"))
        await fulfillment(of: [started], timeout: 2)
        fixture.model.cancel()
        await Task.yield()

        XCTAssertEqual(fixture.model.phase, .idle)
        XCTAssertEqual(fixture.clipboard.string(forType: .string), "keep me")
        XCTAssertFalse(fixture.model.isPasteLeasePending)
    }

    func testSignInFailureNoticeDoesNotOfferPaste() {
        let failure = DictationFailure(transcriptionError: DictationError.signInRequired)
        let state = DictationOverlayState(phase: .failed(failure), elapsed: 0, level: 0)
        XCTAssertEqual(failure.overlayMessage, "Sign in to ChatGPT")
        XCTAssertEqual(state, .message(label: "Sign in to ChatGPT", kind: .warning))
    }

    @MainActor
    private final class Fixture {
        let suite = "clipboard-model-\(UUID().uuidString)"
        let defaults: UserDefaults
        let clipboard: NSPasteboard
        let model: AppModel

        init(automaticPaste: Bool,
             transcribe: @escaping @Sendable (URL) async throws -> String = { _ in "Spoken line" }) {
            _ = NSApplication.shared
            defaults = UserDefaults(suiteName: suite)!
            clipboard = NSPasteboard.withUniqueName()
            clipboard.clearContents()
            clipboard.setString("keep me", forType: .string)
            let preferences = AppPreferences(defaults: defaults)
            preferences.automaticPaste = automaticPaste
            var environment = PasteCoordinator.Environment.live
            environment.restoreDelay = 0
            environment.isAccessibilityTrusted = { true }
            environment.captureFrontmost = {
                PasteTarget(processID: 99, appName: "Notes", focusedElement: nil, focusedWindow: nil)
            }
            environment.isStillFrontmost = { _ in true }
            environment.insertSelectedText = { _, _ in false }
            environment.injectPaste = { true }
            model = AppModel(preferences: preferences, pasteboard: clipboard,
                             history: TranscriptionHistory(fileURL: FileManager.default.temporaryDirectory
                                .appendingPathComponent("gpt-voice-test-\(UUID().uuidString)/history.json")),
                             pasteEnvironment: environment, transcribeAudio: transcribe)
        }

        func cleanup() {
            model.cleanup()
            clipboard.releaseGlobally()
            defaults.removePersistentDomain(forName: suite)
        }

        func waitUntil(_ condition: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(2)
            while !condition(), Date() < deadline {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTAssertTrue(condition(), "Model did not reach the expected phase")
        }
    }
}
