import Foundation

/// User-visible product name, also the bundle executable. The SPM target stays GPTVoice and the
/// bundle identifier stays com.vishesh.codex-dictation so Keychain items and permissions carry over.
enum AppBrand {
    static let displayName = "Goice"
    static let appFolderName = "Goice.app"
    static let applicationsPath = "/Applications/Goice.app"
}
