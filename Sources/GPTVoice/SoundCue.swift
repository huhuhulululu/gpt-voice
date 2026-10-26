import AppKit

enum SoundCue {
    case start
    case stop
    case failure

    func play() {
        Self.sound(for: self)?.play()
    }

    /// Trackpad tap. Off unless the user enables haptic cues. No-op on a mouse-only Mac.
    func haptic() {
        let pattern: NSHapticFeedbackManager.FeedbackPattern
        switch self {
        case .start: pattern = .alignment
        case .stop: pattern = .levelChange
        case .failure: pattern = .generic
        }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    /// Loads the system sounds once so the first hold does not hit disk.
    static func warm() {
        _ = startSound
        _ = stopSound
        _ = failureSound
    }

    private static let cueVolume: Float = 0.32

    private static let startSound = prepared("Tink")
    private static let stopSound = prepared("Pop")
    private static let failureSound = prepared("Basso")

    private static func prepared(_ name: String) -> NSSound? {
        let sound = NSSound(named: NSSound.Name(name))
        sound?.volume = cueVolume
        return sound
    }

    private static func sound(for cue: SoundCue) -> NSSound? {
        switch cue {
        case .start: return startSound
        case .stop: return stopSound
        case .failure: return failureSound
        }
    }
}
