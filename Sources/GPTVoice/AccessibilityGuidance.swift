import Foundation

/// Shared Accessibility recovery copy. Used in Settings, the overlay, and history tooltips.
/// Never includes transcripts, tokens, or other private content.
enum AccessibilityGuidance {
    static let staleGrant = "After an update, a Developer ID reinstall, or a new signature, macOS can keep an old Accessibility entry that no longer matches this app. In System Settings → Privacy & Security → Accessibility, turn \(AppBrand.displayName) off and on, or remove it with − and add \(AppBrand.applicationsPath). Then reopen \(AppBrand.displayName)."

    static let overlayStaleGrant = "Automatic paste failed. After a Developer ID reinstall, turn \(AppBrand.displayName) off and on in System Settings → Privacy & Security → Accessibility. Press ⌘V to paste this result."
}
