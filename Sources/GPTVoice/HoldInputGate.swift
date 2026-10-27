import AppKit
import Carbon.HIToolbox

/// Hold-to-talk must not see keystrokes meant for SecurityAgent / secure fields.
enum HoldInputGate {
    static let authBundleIDs: Set<String> = [
        "com.apple.SecurityAgent",
        "com.apple.authorizationhost",
        "com.apple.CoreAuthAgent",
        "com.apple.localauthentication.UIHelper"
    ]

    static var shouldBypass: Bool {
        shouldBypass(secureInput: IsSecureEventInputEnabled(),
                     frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    static func shouldBypass(secureInput: Bool, frontmostBundleID: String?) -> Bool {
        if secureInput { return true }
        guard let frontmostBundleID else { return false }
        return authBundleIDs.contains(frontmostBundleID)
    }
}
