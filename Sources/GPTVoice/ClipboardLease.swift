import Foundation

/// Decides whether an automatic-paste clipboard lease can be given back.
enum ClipboardLease {
    /// Restore when we still own the change count, or when a clipboard helper
    /// rewrote the same transcript and left our text sitting on the pasteboard.
    static func shouldRestore(ownedChange: Int, currentChange: Int,
                              written: String, currentString: String?) -> Bool {
        currentChange == ownedChange || currentString == written
    }
}
