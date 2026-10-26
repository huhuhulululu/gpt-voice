import AppKit
import ApplicationServices

/// The app and, when Accessibility allows it, the focused element and window at recording start.
struct PasteTarget {
    let processID: pid_t
    let appName: String?
    let focusedElement: AXUIElement?
    let focusedWindow: AXUIElement?

    /// Captures the frontmost app. Returns nil when this app is frontmost.
    static func captureFrontmost() -> PasteTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let pid = app.processIdentifier
        let focus: (element: AXUIElement?, window: AXUIElement?) =
            AccessibilityPermission.check() ? focusedAttributes(of: pid) : (element: nil, window: nil)
        return PasteTarget(processID: pid, appName: app.localizedName,
                           focusedElement: focus.element, focusedWindow: focus.window)
    }

    /// True when the captured app is still frontmost.
    /// Accessibility element objects are not stable across queries. Comparing them
    /// made a field that never changed look like a different target, so the
    /// transcript was copied and never inserted.
    func isStillFrontmost() -> Bool {
        Self.deliveryStillValid(capturedPID: processID,
                                frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }

    static func deliveryStillValid(capturedPID: pid_t, frontmostPID: pid_t?) -> Bool {
        frontmostPID == capturedPID
    }

    /// This process is frontmost. The overlay or an activation can do that without the user switching apps.
    static func isOwnAppFrontmost(
        frontmostPID: pid_t? = NSWorkspace.shared.frontmostApplication?.processIdentifier,
        ownPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> Bool {
        frontmostPID == ownPID
    }

    /// Own-app foreground is not a user app-switch. A different third-party app is.
    static func shouldAttemptAutomaticDelivery(capturedPID: pid_t, frontmostPID: pid_t?, ownPID: pid_t) -> Bool {
        guard let frontmostPID else { return false }
        return frontmostPID == capturedPID || frontmostPID == ownPID
    }

    /// Raises the captured window and activates the app so insert or Command–V can land.
    @discardableResult
    func activateForDelivery() -> Bool {
        if let focusedWindow {
            AXUIElementPerformAction(focusedWindow, kAXRaiseAction as CFString)
        }
        return NSRunningApplication(processIdentifier: processID)?
            .activate(options: [.activateIgnoringOtherApps]) ?? false
    }

    /// Inserts text at the caret. Does not read or replace the rest of the field, and does not use the clipboard.
    static func insertSelectedText(_ text: String, into pid: pid_t) -> Bool {
        guard !text.isEmpty, let element = focusedElement(of: pid) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    static func focusedElement(of pid: pid_t) -> AXUIElement? {
        copyElement(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute)
    }

    private static func focusedAttributes(of pid: pid_t) -> (element: AXUIElement?, window: AXUIElement?) {
        let app = AXUIElementCreateApplication(pid)
        return (copyElement(app, kAXFocusedUIElementAttribute), copyElement(app, kAXFocusedWindowAttribute))
    }

    private static func copyElement(_ owner: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(owner, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
