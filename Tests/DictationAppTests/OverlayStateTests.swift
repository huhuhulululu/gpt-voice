import DictationCore
import XCTest
@testable import GPTVoice

final class OverlayStateTests: XCTestCase {
    func testPreparingUsesTheRecordingSurface() {
        let state = DictationOverlayState(phase: .preparing, elapsed: 0, level: 0)
        XCTAssertEqual(state, .recording(elapsed: 0, level: 0))
        XCTAssertEqual(state.transitionID, "recording")
    }

    func testPreparingAndRecordingShareATransition() {
        let preparing = DictationOverlayState(phase: .preparing, elapsed: 0, level: 0)
        let recording = DictationOverlayState(phase: .recording, elapsed: 1.2, level: 0.4)
        XCTAssertEqual(preparing.transitionID, recording.transitionID)
    }

    func testPreparingStatusMatchesListening() {
        XCTAssertEqual(DictationPhase.preparing.statusText, "Listening…")
        XCTAssertEqual(DictationPhase.preparing.statusText, DictationPhase.recording.statusText)
    }

    func testFinishedNoticesStillHaveHoldTimes() {
        let timing = OverlayTiming()
        XCTAssertNil(timing.hold(for: .recording(elapsed: 0, level: 0)))
        XCTAssertEqual(timing.hold(for: .success(label: "Pasted")), timing.success)
        XCTAssertEqual(timing.hold(for: .message(label: "Press ⌘V to paste", kind: .info)), timing.pasteHint)
        XCTAssertEqual(timing.hold(for: .message(label: "Sign in to ChatGPT", kind: .warning,
                                                actionTitle: "Sign in")), timing.recoveryHint)
        XCTAssertLessThan(timing.pasteHint, 3)
    }

    func testTranscribingAndPastingShareAWorkingSurface() {
        let transcribing = DictationOverlayState(phase: .transcribing, elapsed: 0, level: 0)
        let pasting = DictationOverlayState(phase: .pasting, elapsed: 0, level: 0)
        XCTAssertEqual(transcribing.transitionID, pasting.transitionID)
        XCTAssertEqual(transcribing.transitionID, "working")
        XCTAssertNotEqual(transcribing.transitionID, DictationOverlayState(phase: .recording, elapsed: 0, level: 0).transitionID)
    }

    func testCopiedOverlayHintsNameTheReasonWithoutTheTranscript() {
        XCTAssertEqual(DictationOverlayState(phase: .finished(.copied(.automaticPasteOff)), elapsed: 0, level: 0),
                       .message(label: "Press ⌘V to paste", kind: .info))
        XCTAssertEqual(DictationOverlayState(phase: .finished(.copied(.accessibilityMissing)), elapsed: 0, level: 0,
                                            manualPasteHelpDismissed: true),
                       .message(label: "Press ⌘V · Accessibility off", kind: .info))
        XCTAssertEqual(DictationOverlayState(phase: .finished(.copied(.targetChanged)), elapsed: 0, level: 0),
                       .message(label: "Press ⌘V · app changed", kind: .info))
        let secret = "sk-live-not-a-real-secret"
        for hint in [PasteOutcome.ManualReason.automaticPasteOff.overlayHint,
                     .accessibilityMissing.overlayHint,
                     .targetChanged.overlayHint,
                     .noTarget.overlayHint,
                     .injectionFailed.overlayHint] {
            XCTAssertFalse(hint.contains(secret))
            XCTAssertFalse(hint.contains("token"))
        }
    }

    func testInjectionFailureShowsAccessibilityRecovery() {
        let state = DictationOverlayState(phase: .finished(.copied(.injectionFailed)), elapsed: 0, level: 0)
        guard case .notice(let notice) = state else {
            return XCTFail("Injection failure should explain the Accessibility re-toggle")
        }
        XCTAssertEqual(notice.actionTitle, "Open Accessibility")
        XCTAssertTrue(notice.message.contains("Developer ID"))
        XCTAssertTrue(notice.message.contains("Accessibility"))
        XCTAssertFalse(notice.message.contains("sk-"))
    }

    func testFirstAccessibilityCopyMentionsReinstall() {
        let state = DictationOverlayState(phase: .finished(.copied(.accessibilityMissing)), elapsed: 0, level: 0,
                                          manualPasteHelpDismissed: false)
        guard case .notice(let notice) = state else {
            return XCTFail("First Accessibility fallback should stay a help card")
        }
        XCTAssertEqual(notice.actionTitle, "Open Accessibility")
        XCTAssertTrue(notice.message.contains("Developer ID reinstall"))
        XCTAssertTrue(notice.message.contains("off and on"))
    }

    func testPermissionFailuresOfferTheMatchingOverlayAction() {
        let signIn = DictationFailure(transcriptionError: DictationError.signInRequired)
        XCTAssertEqual(signIn.overlayActionTitle, "Sign in")
        XCTAssertEqual(DictationOverlayState(phase: .failed(signIn), elapsed: 0, level: 0),
                       .message(label: "Sign in to ChatGPT", kind: .warning, actionTitle: "Sign in"))

        let microphone = DictationFailure(captureError: .microphoneDenied, audioKept: false)
        XCTAssertEqual(microphone.overlayActionTitle, "Open Settings")
        XCTAssertEqual(DictationOverlayState(phase: .failed(microphone), elapsed: 0, level: 0),
                       .message(label: "Microphone access is off", kind: .warning, actionTitle: "Open Settings"))
    }
}
