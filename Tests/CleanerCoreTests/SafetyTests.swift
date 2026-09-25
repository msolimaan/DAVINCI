@testable import CleanerCore
import XCTest

final class SafetyGuardTests: XCTestCase {
    private var sandbox: Sandbox!
    private var safety: SafetyGuard!

    override func setUpWithError() throws {
        sandbox = try Sandbox()
        safety = SafetyGuard(homeDirectory: sandbox.root)
    }

    func testAllowsItemsStrictlyInsideTheirRoot() throws {
        let caches = try sandbox.makeFolder("Library/Caches")
        let item = try sandbox.makeFolder("Library/Caches/com.vendor.app")
        XCTAssertEqual(safety.check(item, allowedRoot: caches), .allowed)
    }

    func testDeniesTheRootItself() throws {
        let caches = try sandbox.makeFolder("Library/Caches")
        XCTAssertFalse(safety.check(caches, allowedRoot: caches).isAllowed)
    }

    func testDeniesItemsOutsideTheRoot() throws {
        let caches = try sandbox.makeFolder("Library/Caches")
        let document = try sandbox.makeFile("Documents/thesis.pages")
        XCTAssertFalse(safety.check(document, allowedRoot: caches).isAllowed)
    }

    func testDeniesPathTraversal() throws {
        let caches = try sandbox.makeFolder("Library/Caches")
        try sandbox.makeFile("Documents/thesis.pages")
        let sneaky = caches.appendingPathComponent("../../Documents/thesis.pages")
        XCTAssertFalse(safety.check(sneaky, allowedRoot: caches).isAllowed)
    }

    func testDeniesHomeAndEssentialFolders() throws {
        try sandbox.makeFolder("Documents")
        try sandbox.makeFolder("Library/Caches")
        XCTAssertFalse(safety.check(sandbox.root, allowedRoot: sandbox.root.deletingLastPathComponent()).isAllowed)
        XCTAssertFalse(safety.check(sandbox.url("Documents"), allowedRoot: sandbox.root).isAllowed)
        XCTAssertFalse(safety.check(sandbox.url("Library/Caches"), allowedRoot: sandbox.url("Library")).isAllowed)
    }

    func testFilesInsideEssentialFoldersAreAllowed() throws {
        let file = try sandbox.makeFile("Downloads/installer.dmg")
        XCTAssertEqual(safety.check(file, allowedRoot: sandbox.root), .allowed)
    }

    func testSealedFoldersAreNeverTouched() throws {
        let key = try sandbox.makeFile(".ssh/id_ed25519")
        XCTAssertFalse(safety.check(key, allowedRoot: sandbox.root).isAllowed)
        let keychain = try sandbox.makeFile("Library/Keychains/login.keychain-db")
        XCTAssertFalse(safety.check(keychain, allowedRoot: sandbox.url("Library/Keychains")).isAllowed)
    }

    func testSystemLocationsAreDenied() {
        let system = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        XCTAssertFalse(safety.check(system, allowedRoot: URL(fileURLWithPath: "/System/Library")).isAllowed)
        let usr = URL(fileURLWithPath: "/usr/local/bin/tool")
        XCTAssertFalse(safety.check(usr, allowedRoot: URL(fileURLWithPath: "/usr/local")).isAllowed)
        XCTAssertFalse(safety.check(URL(fileURLWithPath: "/"), allowedRoot: URL(fileURLWithPath: "/")).isAllowed)
    }

    func testSymlinkedParentCannotEscapeTheRoot() throws {
        let caches = try sandbox.makeFolder("Library/Caches")
        try sandbox.makeFile("Documents/secret.txt")
        let link = caches.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: sandbox.url("Documents"))
        // Removing "link" itself is fine (it only deletes the link), but going *through* it is not.
        XCTAssertEqual(safety.check(link, allowedRoot: caches), .allowed)
        XCTAssertFalse(safety.check(link.appendingPathComponent("secret.txt"), allowedRoot: caches).isAllowed)
    }
}

final class RemoverTests: XCTestCase {
    private var sandbox: Sandbox!
    private var remover: Remover!

    override func setUpWithError() throws {
        sandbox = try Sandbox()
        remover = Remover(safety: SafetyGuard(homeDirectory: sandbox.root))
    }

    func testPermanentRemovalDeletesAndReportsSize() throws {
        let root = try sandbox.makeFolder("Library/Caches")
        let item = try sandbox.makeFile("Library/Caches/app/cache.db", bytes: 10_000)
        let folder = item.deletingLastPathComponent()
        let report = remover.remove([RemovalTarget(url: folder, allowedRoot: root, size: 10_000)], mode: .deletePermanently)
        XCTAssertEqual(report.removed, [folder])
        XCTAssertEqual(report.freedBytes, 10_000)
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertFalse(sandbox.exists("Library/Caches/app"))
    }

    func testUnsafeTargetsAreRefusedAndKept() throws {
        let root = try sandbox.makeFolder("Library/Caches")
        try sandbox.makeFile("Documents/keep.txt")
        let report = remover.remove(
            [RemovalTarget(url: sandbox.url("Documents/keep.txt"), allowedRoot: root, size: 1)],
            mode: .deletePermanently
        )
        XCTAssertTrue(report.removed.isEmpty)
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertTrue(sandbox.exists("Documents/keep.txt"))
    }

    func testMissingItemsAreSkippedQuietly() throws {
        let root = try sandbox.makeFolder("Library/Caches")
        let report = remover.remove(
            [RemovalTarget(url: root.appendingPathComponent("gone"), allowedRoot: root, size: 5)],
            mode: .deletePermanently
        )
        XCTAssertTrue(report.removed.isEmpty)
        XCTAssertTrue(report.failures.isEmpty)
    }

    func testPrivilegedCommandOnlyIncludesSafeTargets() throws {
        let root = try sandbox.makeFolder("Library/Caches")
        let good = try sandbox.makeFile("Library/Caches/it's here")
        let bad = try sandbox.makeFile("Documents/keep.txt")
        let command = remover.privilegedRemovalCommand(for: [
            RemovalTarget(url: good, allowedRoot: root, size: 1),
            RemovalTarget(url: bad, allowedRoot: root, size: 1),
        ])
        XCTAssertNotNil(command)
        XCTAssertTrue(command!.hasPrefix("/bin/rm -rf -- "))
        XCTAssertTrue(command!.contains("it'\\''s here"))
        XCTAssertFalse(command!.contains("keep.txt"))
    }
}

final class CommandRunnerTests: XCTestCase {
    func testShellQuoting() {
        XCTAssertEqual(CommandRunner.shellQuote("plain"), "'plain'")
        XCTAssertEqual(CommandRunner.shellQuote("it's"), "'it'\\''s'")
    }

    func testAppleScriptEscaping() {
        XCTAssertEqual(CommandRunner.appleScriptEscaped(#"say "hi" \ bye"#), #"say \"hi\" \\ bye"#)
    }

    func testRunsCommands() async {
        let result = await CommandRunner.run("echo hello; exit 3")
        XCTAssertEqual(result.output, "hello")
        XCTAssertEqual(result.exitCode, 3)
        XCTAssertFalse(result.succeeded)
    }
}
