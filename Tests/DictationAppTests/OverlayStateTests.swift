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
    }
}
