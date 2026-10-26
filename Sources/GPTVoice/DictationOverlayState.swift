import Foundation

/// What the overlay shows. Built from the model, or set explicitly for the Appearance preview.
enum DictationOverlayState: Equatable {
    case hidden
    case recording(elapsed: TimeInterval, level: Float)
    case working(label: String, cancellable: Bool)
    case success(label: String)
    case message(label: String, kind: OverlayMessageKind, actionTitle: String? = nil)
    case notice(DictationOverlayNotice)

    init(phase: DictationPhase, elapsed: TimeInterval, level: Float, manualPasteHelpDismissed: Bool = true) {
        switch phase {
        case .idle:
            self = .hidden
        case .preparing, .recording:
            // Show the live pill immediately. Waiting for the microphone used to
            // flash a "Starting" state and resize the overlay on the first hold.
            self = .recording(elapsed: elapsed, level: level)
        case .transcribing:
            self = .working(label: "Transcribing", cancellable: true)
        case .pasting:
            self = .working(label: "Pasting", cancellable: false)
        case .finished(.pasted):
            self = .success(label: "Pasted")
        case .finished(.previewed):
            self = .success(label: "Preview ready")
        case .finished(.copied(.accessibilityMissing)) where !manualPasteHelpDismissed:
            self = .notice(DictationOverlayNotice(title: "Copied to clipboard",
                message: "Press ⌘V to paste. Allow Accessibility in System Settings. After a Developer ID reinstall, turn GPT Voice off and on there if the switch already looks on.",
                actionTitle: "Open Accessibility"))
        case .finished(.copied(.injectionFailed)):
            self = .notice(DictationOverlayNotice(title: "Copied to clipboard",
                message: AccessibilityGuidance.overlayStaleGrant,
                actionTitle: "Open Accessibility"))
        case .finished(.copied(let reason)):
            self = .message(label: reason.overlayHint, kind: .info)
        case .finished(.preservedNewerClipboard):
            self = .message(label: "Transcript ready · Copy from menu", kind: .info)
        case .failed(let failure):
            self = .message(label: failure.overlayMessage, kind: failure.kind == .noSpeech ? .noSpeech : .warning,
                           actionTitle: failure.overlayActionTitle)
        }
    }

    var transitionID: String {
        switch self {
        case .hidden: return "hidden"
        case .recording: return "recording"
        // Transcribing and Pasting share one surface so the spinner does not remount.
        case .working: return "working"
        case .success(let label): return "success-\(label)"
        case .message(let label, _, let actionTitle):
            return actionTitle.map { "message-\(label)-\($0)" } ?? "message-\(label)"
        case .notice: return "manual-paste-help"
        }
    }

    var isHelp: Bool {
        if case .notice = self { return true }
        return false
    }

    var announcement: String? {
        switch self {
        case .success(let label), .message(let label, _, _): return label
        case .notice(let notice): return "\(notice.title). \(notice.message)"
        case .hidden, .recording, .working: return nil
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
