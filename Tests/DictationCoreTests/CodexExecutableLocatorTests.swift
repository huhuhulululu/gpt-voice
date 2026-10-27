import XCTest
@testable import DictationCore

final class CodexExecutableLocatorTests: XCTestCase {
    private var root: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent("codex-locator-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
    }

    private var roots: CodexExecutableLocator.Roots {
        .init(homebrewPrefixes: [root.path + "/opt/homebrew", root.path + "/usr/local"],
              applications: [root.path + "/Applications"],
              home: root.path + "/home",
              environmentPath: root.path + "/path-bin:relative/bin")
    }

    @discardableResult
    private func file(_ relative: String, executable: Bool = true) throws -> String {
        let url = root.appendingPathComponent(relative)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try fileManager.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
        return url.path
    }

    private func located() -> String? {
        CodexExecutableLocator.locate(roots, fileManager: fileManager)?.path
    }

    func testFindsNothingWhenNothingIsInstalled() {
        XCTAssertNil(located())
    }

    func testIncompleteCaskFallsThroughToTheChatGPTBundle() throws {
        try file("opt/homebrew/Caskroom/codex/0.160.0/codex-code-mode-host")
        let bundled = try file("Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
        try file("Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex")
        XCTAssertEqual(located(), bundled)
    }

    func testNewestStableCaskWinsOverUpgradingAndOlder() throws {
        try file("opt/homebrew/Caskroom/codex/0.9.0/codex")
        let newest = try file("opt/homebrew/Caskroom/codex/0.160.0/codex-aarch64-apple-darwin")
        try file("opt/homebrew/Caskroom/codex/0.161.0.upgrading/bin/codex")
        try file("Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex")
        XCTAssertEqual(located(), newest)
    }

    func testUpgradingCaskIsUsedWhenItIsTheOnlyOneThatWorks() throws {
        try file("opt/homebrew/Caskroom/codex/0.160.0/codex-code-mode-host")
        let upgrading = try file("opt/homebrew/Caskroom/codex/0.161.0.upgrading/bin/codex")
        XCTAssertEqual(located(), upgrading)
    }

    func testSymlinkIsResolvedAndDirectoriesAndPlainFilesAreSkipped() throws {
        try fileManager.createDirectory(atPath: root.path + "/opt/homebrew/Caskroom/codex/0.170.0/codex",
                                        withIntermediateDirectories: true)
        try file("opt/homebrew/Caskroom/codex/0.169.0/codex", executable: false)
        let target = try file("cellar/codex-real")
        try fileManager.createDirectory(atPath: root.path + "/opt/homebrew/bin", withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(atPath: root.path + "/opt/homebrew/bin/codex", withDestinationPath: target)
        XCTAssertEqual(located(), URL(fileURLWithPath: target).resolvingSymlinksInPath().path)
    }

    func testDanglingSymlinkFallsThroughToConductorThenPath() throws {
        try fileManager.createDirectory(atPath: root.path + "/opt/homebrew/bin", withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(atPath: root.path + "/opt/homebrew/bin/codex",
                                           withDestinationPath: root.path + "/missing/codex")
        let onPath = try file("path-bin/codex")
        XCTAssertEqual(located(), onPath)
        let conductor = try file("home/Library/Application Support/com.conductor.app/bin/codex")
        XCTAssertEqual(located(), conductor)
    }

    func testCandidateOrderAndRelativePathEntriesAreIgnored() throws {
        try file("opt/homebrew/Caskroom/codex/0.160.0/bin/codex")
        let candidates = CodexExecutableLocator.candidates(roots)
        let order = [
            root.path + "/opt/homebrew/Caskroom/codex/0.160.0/bin/codex",
            root.path + "/opt/homebrew/bin/codex",
            root.path + "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            root.path + "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
            root.path + "/home/Library/Application Support/com.conductor.app/bin/codex",
            root.path + "/home/.local/bin/codex",
            root.path + "/path-bin/codex",
        ]
        let positions = order.compactMap { candidates.firstIndex(of: $0) }
        XCTAssertEqual(positions.count, order.count)
        XCTAssertEqual(positions, positions.sorted())
        XCTAssertFalse(candidates.contains { $0.hasPrefix("relative") })
        XCTAssertEqual(candidates.count, Set(candidates).count)
    }

    func testCaskVersionOrdering() {
        XCTAssertEqual(CodexExecutableLocator.sortedCaskVersions(
            ["0.9.0", "0.161.0.upgrading", "0.160.0", ".metadata", "0.160.1", "latest"]),
            ["0.160.1", "0.160.0", "0.9.0", "0.161.0.upgrading", "latest"])
    }
}
