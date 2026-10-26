import AppKit

/// Watches for one modifier key tapped by itself, in this app and in others.
/// The event is never swallowed, so a chord still reaches the frontmost app.
final class ModifierTapListener {
    private var tracker: ModifierTapTracker
    private let onTap: @MainActor () -> Void
    private var monitors: [Any] = []
    /// Last device-dependent modifier bits. `flagsChanged` key codes are not reliable.
    private var deviceFlags: UInt = 0

    init(keyCode: UInt32, onTap: @escaping @MainActor () -> Void) {
        tracker = ModifierTapTracker(keyCode: keyCode)
        self.onTap = onTap
    }

    deinit { stop() }

    /// Installs the monitors. Returns false when macOS will not deliver global key events.
    func start() -> Bool {
        stop()
        let mask: NSEvent.EventTypeMask = [
            .flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel
        ]
        guard let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
        }) else { return false }
        monitors.append(global)
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
            return event
        }) {
            monitors.append(local)
        }
        return true
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        tracker.reset()
        deviceFlags = 0
    }

    private func handle(_ event: NSEvent) {
        let fired: Bool
        switch event.type {
        case .flagsChanged:
            fired = consumeFlags(event)
        case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
            fired = tracker.consume(
                eventKeyCode: nil,
                modifierDown: false,
                otherModifierDown: false,
                timestamp: event.timestamp,
                cancelsTap: true)
        default:
            return
        }
        guard fired else { return }
        DispatchQueue.main.async { [onTap] in onTap() }
    }

    /// Uses the changed device-dependent bit, not `NSEvent.keyCode`.
    private func consumeFlags(_ event: NSEvent) -> Bool {
        let raw = UInt(event.modifierFlags.rawValue)
        let current = raw & HotkeySpec.deviceModifierMasks
        let changed = deviceFlags ^ current
        deviceFlags = current
        let watched = tracker.keyCode
        if changed == 0 {
            return tracker.consume(eventKeyCode: nil, modifierDown: false, otherModifierDown: false,
                                   timestamp: event.timestamp, cancelsTap: false)
        }
        // More than one modifier bit changed in this event. That is a chord, not a tap.
        if changed & (changed - 1) != 0 {
            return tracker.consume(eventKeyCode: nil, modifierDown: false, otherModifierDown: true,
                                   timestamp: event.timestamp, cancelsTap: false)
        }
        let code = HotkeySpec.keyCode(forDeviceMask: changed)
        let down = current & changed != 0
        return tracker.consume(
            eventKeyCode: code,
            modifierDown: down && code == watched,
            otherModifierDown: HotkeySpec.hasOtherDeviceModifier(than: watched, rawFlags: raw),
            timestamp: event.timestamp,
            cancelsTap: false)
    }
}
