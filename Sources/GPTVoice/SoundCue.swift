import AppKit

enum SoundCue {
    case start
    case stop
    case failure

    func play() {
        Self.sound(for: self)?.play()
    }

    /// Loads the system sounds once so the first hold does not hit disk.
    static func warm() {
        _ = startSound
        _ = stopSound
        _ = failureSound
    }

    private static let startSound = NSSound(named: NSSound.Name("Tink"))
    private static let stopSound = NSSound(named: NSSound.Name("Pop"))
    private static let failureSound = NSSound(named: NSSound.Name("Basso"))

    private static func sound(for cue: SoundCue) -> NSSound? {
        switch cue {
        case .start: return startSound
        case .stop: return stopSound
        case .failure: return failureSound
        }
    }
}
