import Foundation

/// The result of delivering a transcript. The caller keeps the original transcript in memory in all cases.
enum PasteOutcome: Equatable {
    /// The practice result is visible in the app. The clipboard was not changed.
    case previewed
    enum ManualReason: String, Codable, Equatable, Sendable {
        case automaticPasteOff
        case accessibilityMissing
        case targetChanged
        case noTarget
        case injectionFailed
    }

    /// Text was pasted into the original app.
    case pasted(appName: String?)
    /// Text is on the clipboard. The user must paste it.
    case copied(ManualReason)
    /// The clipboard changed during dictation. It was not replaced. Offer Copy.
    case preservedNewerClipboard

    var message: String {
        switch self {
        case .previewed:
            return "Practice text is ready. Your clipboard was not changed."
        case .pasted(let name):
            return name.map { "Pasted into \($0)." } ?? "Pasted."
        case .copied(.automaticPasteOff):
            return "Copied. Press ⌘V to paste."
        case .copied(.accessibilityMissing):
            return "Copied. Accessibility is off, so press ⌘V to paste."
        case .copied(.targetChanged):
            return "Copied. You changed apps, so automatic paste was skipped. Press ⌘V to paste."
        case .copied(.noTarget):
            return "Copied. No target app was found. Press ⌘V to paste."
        case .copied(.injectionFailed):
            return "Copied. Automatic paste failed. Re-toggle Accessibility if you just reinstalled, then press ⌘V."
        case .preservedNewerClipboard:
            return "Your clipboard changed, so it was not replaced. Select Copy to copy the transcript."
        }
    }
}

extension PasteOutcome.ManualReason {
    /// Short overlay hint for a copied result. Never includes transcript text.
    var overlayHint: String {
        switch self {
        case .automaticPasteOff, .noTarget:
            return "Press ⌘V to paste"
        case .accessibilityMissing:
            return "Press ⌘V · Accessibility off"
        case .targetChanged:
            return "Press ⌘V · app changed"
        case .injectionFailed:
            return "Press ⌘V · paste failed"
        }
    }

    /// History row caption. Never includes transcript text or secrets.
    var historyCaption: String {
        switch self {
        case .automaticPasteOff: return "Copied · paste off"
        case .accessibilityMissing: return "Copied · Accessibility off"
        case .targetChanged: return "Copied · app changed"
        case .noTarget: return "Copied · no target"
        case .injectionFailed: return "Copied · paste failed"
        }
    }

    /// Tooltip guidance for a copied history row. Never includes transcript text or secrets.
    var historyGuidance: String {
        switch self {
        case .automaticPasteOff:
            return "Automatic paste is off. Press ⌘V, or turn paste on in Settings → Paste & behavior."
        case .accessibilityMissing:
            return "Allow \(AppBrand.displayName) in System Settings → Privacy & Security → Accessibility, then reopen the app."
        case .targetChanged:
            return "You changed apps during dictation, so automatic paste was skipped. Press ⌘V."
        case .noTarget:
            return "No target app was found. Press ⌘V to paste."
        case .injectionFailed:
            return AccessibilityGuidance.staleGrant
        }
    }
}
