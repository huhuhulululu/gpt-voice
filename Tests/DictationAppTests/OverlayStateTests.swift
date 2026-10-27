import DictationCore
import Foundation
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
        XCTAssertLessThan(timing.success, 1.3)
        XCTAssertEqual(timing.hold(for: .message(label: "Press ⌘V to paste", kind: .info)), timing.pasteHint)
        XCTAssertLessThan(timing.pasteHint, 2)
        XCTAssertEqual(timing.hold(for: .message(label: "Sign in to ChatGPT", kind: .warning,
                                                actionTitle: "Sign in")), timing.recoveryHint)
    }

    func testTranscribingAndPastingShareAWorkingSurface() {
        let transcribing = DictationOverlayState(phase: .transcribing, elapsed: 0, level: 0)
        let pasting = DictationOverlayState(phase: .pasting, elapsed: 0, level: 0)
        XCTAssertEqual(transcribing.transitionID, pasting.transitionID)
        XCTAssertEqual(transcribing, .working(label: "Transcribing…", cancellable: true))
        XCTAssertEqual(pasting, .working(label: "Pasting…", cancellable: false))
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

        let key = DictationFailure(transcriptionError: DictationError.apiKeyRejected)
        XCTAssertEqual(key.recovery, .transcriptionSettings)
        XCTAssertEqual(key.overlayActionTitle, "Open Settings")
        XCTAssertEqual(DictationOverlayState(phase: .failed(key), elapsed: 0, level: 0),
                       .message(label: "Check the API key", kind: .warning, actionTitle: "Open Settings"))

        let endpoint = DictationFailure(transcriptionError: DictationError.invalidEndpoint)
        XCTAssertEqual(endpoint.recovery, .transcriptionSettings)
        XCTAssertEqual(endpoint.overlayMessage, "Check the server URL")
    }

    func testNetworkAndRateLimitKeepRetryWithoutNamingChatGPT() {
        let network = DictationFailure(transcriptionError: URLError(.notConnectedToInternet))
        XCTAssertEqual(network.recovery, .retry)
        XCTAssertEqual(network.overlayActionTitle, "Retry")
        XCTAssertFalse(network.message.contains("ChatGPT"))

        let limited = DictationFailure(transcriptionError: DictationError.service(429))
        XCTAssertEqual(limited.recovery, .retry)
        XCTAssertFalse(limited.message.contains("ChatGPT"))
        XCTAssertTrue(limited.message.contains("request limit"))
    }

    func testTooShortHoldAndKeychainDenialHaveTheirOwnRecovery() {
        let short = DictationFailure(transcriptionError: DictationError.recordingTooShort)
        XCTAssertEqual(short.kind, .noSpeech)
        XCTAssertEqual(short.recovery, .none)
        XCTAssertEqual(DictationOverlayState(phase: .failed(short), elapsed: 0, level: 0),
                       .message(label: "Hold a little longer", kind: .noSpeech))

        let keychain = DictationFailure(transcriptionError: DictationError.keychainUnavailable)
        XCTAssertEqual(keychain.recovery, .retry)
        XCTAssertTrue(keychain.keepsAudio, "Retry resends the same take after Always Allow")
        XCTAssertEqual(DictationOverlayState(phase: .failed(keychain), elapsed: 0, level: 0),
                       .message(label: "Allow Keychain access", kind: .warning, actionTitle: "Retry"))
    }

    func testMeterKeepsQuietSpeechVisible() {
        XCTAssertEqual(AudioCapture.meterLevel(decibels: -60), 0)
        XCTAssertGreaterThan(AudioCapture.meterLevel(decibels: -40), 0.25, "A soft voice still moves the bars")
        XCTAssertEqual(AudioCapture.meterLevel(decibels: -5), 1)
    }

    func testShortUtteranceIsNoSpeechWithoutRetry() {
        let empty = DictationFailure(transcriptionError: DictationError.emptyTranscript)
        XCTAssertEqual(empty.kind, .noSpeech)
        XCTAssertEqual(empty.recovery, .none)
        XCTAssertNil(empty.overlayActionTitle)
        XCTAssertEqual(DictationOverlayState(phase: .failed(empty), elapsed: 0, level: 0),
                       .message(label: "No speech found", kind: .noSpeech))
    }
}
