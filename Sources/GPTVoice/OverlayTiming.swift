import Foundation

struct OverlayTiming {
    var resize: TimeInterval = 0.18
    var entrance: TimeInterval = 0.18
    var exit: TimeInterval = 0.14
    var reducedFade: TimeInterval = 0.08
    var success: TimeInterval = 1.4
    var noSpeech: TimeInterval = 2
    var warning: TimeInterval = 3
    var pasteHint: TimeInterval = 2.2
    var recoveryHint: TimeInterval = 4.2
    var help: TimeInterval = 7.5

    func hold(for state: DictationOverlayState) -> TimeInterval? {
        switch state {
        case .success: return success
        case .message(_, .noSpeech, _): return noSpeech
        case .message(_, _, let actionTitle) where actionTitle != nil: return recoveryHint
        case .message(_, .warning, _): return warning
        case .message(_, .info, _): return pasteHint
        case .notice: return help
        case .hidden, .recording, .working: return nil
        }
    }
}
