@testable import CleanerCore
import XCTest

final class LeftoverMatchingTests: XCTestCase {
    func testMatchesBundleIdentifierVariants() {
        let id = "com.vendor.Editor"
        for name in [
            "com.vendor.Editor",
            "com.vendor.editor.plist",
            "com.vendor.Editor.savedState",
            "com.vendor.Editor.helper",
            "group.com.vendor.Editor",
            "ABCDE12345.com.vendor.Editor.shared",
            "Editor Pro",
            "Editor Pro.plist",
        ] {
            XCTAssertTrue(LeftoverFinder.matches(name, bundleIdentifier: id, appName: "Editor Pro"), name)
        }
    }

    func testDoesNotMatchLookalikes() {
        let id = "com.vendor.Editor"
        for name in [
            "com.vendor.EditorLite",
            "com.vendor",
            "com.other.Editor2",
            "Editor",
            "My Editor Pro Backups",
        ] {
            XCTAssertFalse(LeftoverFinder.matches(name, bundleIdentifier: id, appName: "Editor Pro"), name)
        }
    }

    func testShortAppNamesDoNotMatchByName() {
        XCTAssertFalse(LeftoverFinder.matches("Go", bundleIdentifier: "com.x.go", appName: "Go"))
        XCTAssertTrue(LeftoverFinder.matches("com.x.go", bundleIdentifier: "com.x.go", appName: "Go"))
    }

    func testBundleIdentifierCandidates() {
        XCTAssertEqual(LeftoverFinder.bundleIdentifierCandidate(from: "com.vendor.app.plist"), "com.vendor.app")
        XCTAssertEqual(LeftoverFinder.bundleIdentifierCandidate(from: "com.vendor.App.savedState"), "com.vendor.app")
        XCTAssertNil(LeftoverFinder.bundleIdentifierCandidate(from: "Google"))
        XCTAssertNil(LeftoverFinder.bundleIdentifierCandidate(from: "group.com.vendor.app"))
        XCTAssertNil(LeftoverFinder.bundleIdentifierCandidate(from: "some file.txt"))
    }
}

final class UninstallerTests: XCTestCase {
    private var sandbox: Sandbox!

    override func setUpWithError() throws {
        sandbox = try Sandbox()
    }

    @discardableResult
    private func makeApp(_ name: String, id: String) throws -> URL {
        try sandbox.makePlist("Applications/\(name).app/Contents/Info.plist", [
            "CFBundleIdentifier": id,
            "CFBundleName": name,
            "CFBundleShortVersionString": "2.1",
        ])
        try sandbox.makeFile("Applications/\(name).app/Contents/MacOS/\(name)", bytes: 50_000)
        return sandbox.url("Applications/\(name).app")
    }

    func testInventoryReadsAppsAndSkipsAppleAndSelf() throws {
        try makeApp("Editor", id: "com.vendor.editor")
        try makeApp("Notes", id: "com.apple.Notes")
        try makeApp("DaVinci Cleaner", id: "com.davinci.cleaner")
        try sandbox.makePlist("Applications/Suite/Designer.app/Contents/Info.plist", ["CFBundleIdentifier": "com.vendor.designer"])

        let inventory = AppInventory(searchRoots: [sandbox.url("Applications")])
        let apps = inventory.loadApps(computeSizes: true)
        XCTAssertEqual(apps.map(\.bundleIdentifier), ["com.vendor.designer", "com.vendor.editor"])
        XCTAssertEqual(apps.first { $0.name == "Editor" }?.version, "2.1")
        XCTAssertGreaterThan(apps.first { $0.name == "Editor" }?.size ?? 0, 0)

        let withApple = inventory.loadApps(includeAppleApps: true)
        XCTAssertTrue(withApple.contains { $0.bundleIdentifier == "com.apple.Notes" })
    }

    func testFindsLeftoversAcrossLibraryFolders() throws {
        try sandbox.makeFile("Library/Application Support/Editor/state.json")
        try sandbox.makeFile("Library/Caches/com.vendor.editor/Cache.db")
        try sandbox.makeFile("Library/Preferences/com.vendor.editor.plist")
        try sandbox.makeFile("Library/Containers/com.vendor.editor/Data/x")
        try sandbox.makeFile("Library/Group Containers/TEAM123.com.vendor.editor/x")
        try sandbox.makeFile("Library/Caches/com.vendor.other/Cache.db")
        try sandbox.makeFile("SystemLibrary/LaunchDaemons/com.vendor.editor.helper.plist")

        let finder = LeftoverFinder(home: sandbox.root, systemLibrary: sandbox.url("SystemLibrary"))
        let files = finder.leftovers(bundleIdentifier: "com.vendor.editor", appName: "Editor")
        let names = Set(files.map(\.url.lastPathComponent))
        XCTAssertEqual(names, [
            "Editor",
            "com.vendor.editor",
            "com.vendor.editor.plist",
            "TEAM123.com.vendor.editor",
            "com.vendor.editor.helper.plist",
        ])
        XCTAssertEqual(files.filter(\.isSystemWide).map(\.url.lastPathComponent), ["com.vendor.editor.helper.plist"])

        let safety = SafetyGuard(homeDirectory: sandbox.root)
        XCTAssertTrue(files.allSatisfy { safety.check($0.url, allowedRoot: $0.allowedRoot).isAllowed })
    }

    func testOrphansExcludeInstalledAndAppleIdentifiers() throws {
        try sandbox.makeFile("Library/Preferences/com.gone.app.plist")
        try sandbox.makeFile("Library/Preferences/com.installed.app.plist")
        try sandbox.makeFile("Library/Preferences/com.installed.app.helper.plist")
        try sandbox.makeFile("Library/Preferences/com.apple.finder.plist")
        try sandbox.makeFile("Library/Caches/com.elsewhere.app/x")
        try sandbox.makeFile("Library/Application Support/Some Folder/x")

        let finder = LeftoverFinder(home: sandbox.root, systemLibrary: sandbox.url("SystemLibrary"))
        let orphans = finder.orphans(installedBundleIdentifiers: ["com.installed.app"]) { $0 == "com.elsewhere.app" }
        XCTAssertEqual(orphans.map(\.url.lastPathComponent), ["com.gone.app.plist"])
    }
}

final class MaintenanceTests: XCTestCase {
    func testTaskIdentifiersAreUnique() {
        let ids = MaintenanceTask.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertTrue(ids.allSatisfy { !$0.contains("__") })
    }

    func testBatchOutputParsing() {
        let tasks = Array(MaintenanceTask.all.prefix(3))
        let output = """
        __DAVINCI__\(tasks[0].id)__0
        noise
        __DAVINCI__\(tasks[1].id)__1
        """
        let outcomes = MaintenanceRunner.parseBatchOutput(CommandResult(exitCode: 0, output: output), tasks: tasks)
        XCTAssertEqual(outcomes[tasks[0].id], .succeeded)
        XCTAssertEqual(outcomes[tasks[1].id], .failed("Exited with code 1"))
        XCTAssertNil(outcomes[tasks[2].id])
    }

    func testCancelledPasswordPromptMarksEverythingCancelled() {
        let tasks = Array(MaintenanceTask.all.prefix(2))
        let result = CommandResult(exitCode: 1, output: "execution error: User canceled. (-128)")
        let outcomes = MaintenanceRunner.parseBatchOutput(result, tasks: tasks)
        XCTAssertEqual(outcomes.values.filter { $0 == .cancelled }.count, 2)
    }

    func testBatchedCommandRunsEachTaskAndReportsCodes() async {
        let fake = [
            MaintenanceTask(id: "ok", title: "", summary: "", whenToUse: "", symbolName: "", command: "true", requiresAdministrator: false, isRecommended: false),
            MaintenanceTask(id: "bad", title: "", summary: "", whenToUse: "", symbolName: "", command: "exit 4", requiresAdministrator: false, isRecommended: false),
        ]
        let result = await CommandRunner.run(MaintenanceRunner.batchedCommand(for: fake))
        let outcomes = MaintenanceRunner.parseBatchOutput(result, tasks: fake)
        XCTAssertEqual(outcomes["ok"], .succeeded)
        XCTAssertEqual(outcomes["bad"], .failed("Exited with code 4"))
    }
}

final class LaunchItemTests: XCTestCase {
    func testParsesDisabledServices() {
        let output = """
        disabled services = {
            "com.vendor.updater" => disabled
            "com.vendor.sync" => enabled
            "com.old.agent" => true
        }
        """
        XCTAssertEqual(LaunchItemStore.parseDisabled(output), ["com.vendor.updater", "com.old.agent"])
    }

    func testReadsLaunchAgentPlists() throws {
        let sandbox = try Sandbox()
        try sandbox.makePlist("LaunchAgents/com.vendor.updater.plist", [
            "Label": "com.vendor.updater",
            "ProgramArguments": ["/Applications/Vendor.app/Contents/MacOS/Updater", "--quiet"],
            "RunAtLoad": true,
        ])
        try sandbox.makeFile("LaunchAgents/readme.txt")

        let items = LaunchItemStore.readItems(
            in: sandbox.url("LaunchAgents"),
            scope: .userAgent,
            disabledLabels: ["com.vendor.updater"]
        )
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].displayName, "Updater")
        XCTAssertTrue(items[0].runsAtLoad)
        XCTAssertTrue(items[0].isDisabled)
    }
}

final class SystemStatsTests: XCTestCase {
    func testParsesProcessListSortedByMemory() {
        let output = """
          120   1.5  204800 Safari
          88    0,0   10240 Finder
          7    12.0  512000 Xcode Helper
        garbage line
        """
        let processes = SystemStats.parseProcessList(output)
        XCTAssertEqual(processes.map(\.name), ["Xcode Helper", "Safari", "Finder"])
        XCTAssertEqual(processes.first?.memoryBytes, 512_000 * 1024)
        XCTAssertEqual(processes.first?.cpuPercent, 12.0)
    }

    func testDiskSnapshot() {
        let disk = SystemStats.disk()
        XCTAssertNotNil(disk)
        if let disk {
            XCTAssertGreaterThan(disk.total, 0)
            XCTAssertLessThanOrEqual(disk.available, disk.total)
        }
    }
}
