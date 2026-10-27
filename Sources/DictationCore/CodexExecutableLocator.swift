import Foundation

/// Finds a runnable `codex` binary using fixed install locations only: a few `stat` calls and one
/// small directory listing per Homebrew prefix. No network, no recursive scans.
public enum CodexExecutableLocator {
    public struct Roots: Sendable {
        public var homebrewPrefixes: [String]
        public var applications: [String]
        public var home: String
        public var environmentPath: String

        public init(homebrewPrefixes: [String], applications: [String], home: String, environmentPath: String) {
            self.homebrewPrefixes = homebrewPrefixes
            self.applications = applications
            self.home = home
            self.environmentPath = environmentPath
        }

        public static var system: Roots {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return Roots(homebrewPrefixes: ["/opt/homebrew", "/usr/local"],
                         applications: ["/Applications", home + "/Applications"],
                         home: home,
                         environmentPath: ProcessInfo.processInfo.environment["PATH"] ?? "")
        }
    }

    /// Names the Codex cask ships its binary under. `codex-code-mode-host` is a helper, not the CLI.
    static let caskBinaryNames = ["bin/codex", "codex", "codex-aarch64-apple-darwin", "codex-x86_64-apple-darwin"]

    public static func locate(_ roots: Roots = .system, fileManager: FileManager = .default) -> URL? {
        for path in candidates(roots, fileManager: fileManager) {
            if let url = runnable(path, fileManager: fileManager) { return url }
        }
        return nil
    }

    /// In priority order: Homebrew cask (newest stable version first, then in-progress upgrades),
    /// Homebrew `bin`, the ChatGPT app bundle, Conductor, `~/.local/bin`, then `PATH`.
    public static func candidates(_ roots: Roots, fileManager: FileManager = .default) -> [String] {
        var paths: [String] = []
        for prefix in roots.homebrewPrefixes {
            let caskroom = prefix + "/Caskroom/codex"
            let versions = (try? fileManager.contentsOfDirectory(atPath: caskroom)) ?? []
            for version in sortedCaskVersions(versions) {
                paths += caskBinaryNames.map { "\(caskroom)/\(version)/\($0)" }
            }
        }
        paths += roots.homebrewPrefixes.map { $0 + "/bin/codex" }
        for applications in roots.applications {
            let cli = applications + "/ChatGPT.app/Contents/Resources/codex-cli"
            paths.append(cli + "/CodexCLI.app/Contents/MacOS/codex")
            paths.append(cli + "/bin/codex")
        }
        paths.append(roots.home + "/Library/Application Support/com.conductor.app/bin/codex")
        paths.append(roots.home + "/.local/bin/codex")
        paths += roots.environmentPath.split(separator: ":").filter { $0.hasPrefix("/") }.map { "\($0)/codex" }
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }

    /// Stable versions (digits and dots only) newest first, then anything else such as
    /// `0.161.0.upgrading`, also newest first.
    static func sortedCaskVersions(_ names: [String]) -> [String] {
        let visible = names.filter { !$0.hasPrefix(".") }
        let stable = visible.filter(isStableVersion)
        let other = visible.filter { !isStableVersion($0) }
        return stable.sorted(by: isNewer) + other.sorted(by: isNewer)
    }

    static func isStableVersion(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") }
            && !name.hasPrefix(".") && !name.hasSuffix(".")
    }

    static func isNewer(_ lhs: String, _ rhs: String) -> Bool {
        let a = numericParts(lhs), b = numericParts(rhs)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return lhs > rhs
    }

    private static func numericParts(_ name: String) -> [Int] {
        name.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }

    /// The symlink-resolved file, if it is a regular executable file.
    static func runnable(_ path: String, fileManager: FileManager) -> URL? {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory), !isDirectory.boolValue,
              fileManager.isExecutableFile(atPath: resolved.path) else { return nil }
        return resolved
    }
}
