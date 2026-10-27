import AppKit
import Carbon.HIToolbox

/// Hold-to-talk stands down while a system authentication sheet is taking a password.
/// Secure input alone is not enough: Terminal's Secure Keyboard Entry, password managers, and a
/// stuck secure-input app turn it on globally, and bypassing then would leave Left Option dead.
enum HoldInputGate {
    static let authBundleIDs: Set<String> = [
        "com.apple.SecurityAgent",
        "com.apple.authorizationhost",
        "com.apple.CoreAuthAgent",
        "com.apple.localauthentication.UIHelper"
    ]

    static var shouldBypass: Bool {
        shouldBypass(frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                     secureInputOwnerBundleID: secureInputOwnerBundleID())
    }

    static func shouldBypass(frontmostBundleID: String?, secureInputOwnerBundleID: String?) -> Bool {
        [frontmostBundleID, secureInputOwnerBundleID].contains { id in
            id.map(authBundleIDs.contains) ?? false
        }
    }

    /// The process holding secure input, from the login session. Nil when secure input is off.
    private static func secureInputOwnerBundleID() -> String? {
        guard IsSecureEventInputEnabled(),
              let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let pid = (session["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }
}
