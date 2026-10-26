import AppKit
import ApplicationServices
import Carbon.HIToolbox
import DictationCore

/// Serial owner of the clipboard lease and paste delivery.
/// Call `beginSession()` when recording starts and `deliver(text:automaticPaste:)` when the transcript arrives.
@MainActor
final class PasteCoordinator {
    /// Time that the target app gets to read the pasteboard before the old content returns.
    nonisolated static let restoreDelay: UInt64 = 750_000_000

    struct Environment {
        var restoreDelay: UInt64
        var isAccessibilityTrusted: () -> Bool
        var captureFrontmost: () -> PasteTarget?
        var isStillFrontmost: (PasteTarget) -> Bool
        var insertSelectedText: (String, pid_t) -> Bool
        var injectPaste: () -> Bool

        static let live = Environment(
            restoreDelay: PasteCoordinator.restoreDelay,
            isAccessibilityTrusted: { AccessibilityPermission.check() },
            captureFrontmost: { PasteTarget.captureFrontmost() },
            isStillFrontmost: { $0.isStillFrontmost() },
            insertSelectedText: { PasteTarget.insertSelectedText($0, into: $1) },
            injectPaste: { PasteCoordinator.postCommandV() }
        )
    }

    private let pasteboard: NSPasteboard
    private let environment: Environment
    private var target: PasteTarget?
    /// Captured when the shortcut starts, before the overlay or a clipboard restore can change the frontmost app.
    private var pendingTarget: PasteTarget?
    private var snapshot: ClipboardSnapshot?
    private var delivery: Task<PasteOutcome, Never>?

    init(pasteboard: NSPasteboard = .general, environment: Environment = .live) {
        self.pasteboard = pasteboard
        self.environment = environment
    }

    /// True while a paste or a clipboard restore is pending. Block new recordings while true.
    var isLeasePending: Bool { delivery != nil }

    /// Waits for any pending paste and clipboard restore to finish.
    func waitForLease() async {
        while let pending = delivery { _ = await pending.value }
    }

    /// Remembers the frontmost app at the shortcut, before any later UI.
    func noteIntendedTarget() {
        pendingTarget = environment.captureFrontmost()
    }

    /// Captures the paste target and the clipboard. Call at recording start.
    func beginSession(target: PasteTarget? = nil) {
        self.target = target ?? pendingTarget ?? environment.captureFrontmost()
        pendingTarget = nil
        snapshot = ClipboardSnapshot.capture(pasteboard)
    }

    /// Drops the captured target and clipboard after delivery.
    /// The next recording's intended target is left alone.
    func endSession() {
        target = nil
        snapshot = nil
    }

    /// Drops a target noted for a recording that was cancelled before it started.
    func discardIntendedTarget() {
        pendingTarget = nil
    }

    /// Explicit user Copy. Writes the original transcript.
    func copy(_ text: String) {
        write(text)
    }

    /// Delivers a transcript once. Never replaces a clipboard that changed since `beginSession()`.
    func deliver(text: String, automaticPaste: Bool) async -> PasteOutcome {
        await waitForLease()
        let task = Task { () -> PasteOutcome in
            let outcome = await self.performDelivery(text: text, automaticPaste: automaticPaste)
            self.endSession()
            self.delivery = nil
            return outcome
        }
        delivery = task
        return await task.value
    }

    private func performDelivery(text: String, automaticPaste: Bool) async -> PasteOutcome {
        let insertable = TranscriptText.forAutomaticPaste(text)
        if automaticPaste,
           environment.isAccessibilityTrusted(),
           let target, environment.isStillFrontmost(target),
           environment.insertSelectedText(insertable, target.processID) {
            return .pasted(appName: target.appName)
        }

        if let snapshot, pasteboard.changeCount != snapshot.changeCount {
            return .preservedNewerClipboard
        }
        let reason: PasteOutcome.ManualReason?
        if !automaticPaste {
            reason = .automaticPasteOff
        } else if !environment.isAccessibilityTrusted() {
            reason = .accessibilityMissing
        } else if target == nil || snapshot == nil {
            reason = .noTarget
        } else if !environment.isStillFrontmost(target!) {
            reason = .targetChanged
        } else {
            reason = nil
        }
        if let reason {
            write(text)
            return .copied(reason)
        }

        let ownedChange = write(insertable)
        guard environment.injectPaste() else {
            // Keep the transcript on the clipboard for manual recovery.
            return .copied(.injectionFailed)
        }
        try? await Task.sleep(nanoseconds: environment.restoreDelay)
        restoreClipboardIfStillOwned(written: insertable, ownedChange: ownedChange)
        return .pasted(appName: target?.appName)
    }

    private func restoreClipboardIfStillOwned(written: String, ownedChange: Int) {
        guard let snapshot else { return }
        if ClipboardLease.shouldRestore(ownedChange: ownedChange,
                                        currentChange: pasteboard.changeCount,
                                        written: written,
                                        currentString: pasteboard.string(forType: .string)) {
            snapshot.restore(to: pasteboard)
        }
    }

    @discardableResult
    private func write(_ text: String) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }

    /// Posts Command+V with explicit flags. Never posts Return.
    nonisolated static func postCommandV() -> Bool {
        let source = CGEventSource(stateID: .privateState)
        let key = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
