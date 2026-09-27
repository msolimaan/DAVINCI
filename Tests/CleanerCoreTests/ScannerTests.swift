@testable import CleanerCore
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest

final class JunkScannerTests: XCTestCase {
    private var sandbox: Sandbox!
    private var scanner: JunkScanner!

    override func setUpWithError() throws {
        sandbox = try Sandbox()
        scanner = JunkScanner(catalog: JunkCatalog(home: sandbox.root, systemLibrary: sandbox.url("SystemLibrary")))
    }

    func testUserCachesListsChildrenLargestFirstAndSkipsExclusions() throws {
        try sandbox.makeFile("Library/Caches/com.small.app/data", bytes: 2_000)
        try sandbox.makeFile("Library/Caches/com.big.app/data", bytes: 200_000)
        try sandbox.makeFile("Library/Caches/Google/Chrome/cache", bytes: 50_000)
        try sandbox.makeFile("Library/Caches/CloudKit/state", bytes: 50_000)
        try sandbox.makeFile("Library/Caches/.DS_Store", bytes: 100)

        let items = scanner.scan(.userCaches)
        XCTAssertEqual(items.map(\.name), ["com.big.app", "com.small.app"])
        XCTAssertTrue(items.allSatisfy { $0.allowedRoot.lastPathComponent == "Caches" })
        XCTAssertGreaterThanOrEqual(items[0].size, 200_000)
    }

    func testBrowserCachesAreWholeFolders() throws {
        try sandbox.makeFile("Library/Caches/Google/Chrome/Default/Cache/a", bytes: 30_000)
        let items = scanner.scan(.browserCaches)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.name, "Google Chrome")
        XCTAssertEqual(items.first?.allowedRoot.lastPathComponent, "Google")
    }

    func testXcodeArchivesAreFoundButNotPreselected() throws {
        try sandbox.makeFile("Library/Developer/Xcode/DerivedData/MyApp-abc/Build/x", bytes: 10_000)
        try sandbox.makeFile("Library/Developer/Xcode/Archives/2025-01-01/MyApp.xcarchive/x", bytes: 10_000)
        let items = scanner.scan(.xcodeJunk)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first { $0.name == "MyApp-abc" }?.isSelectedByDefault, true)
        XCTAssertEqual(items.first { $0.name == "2025-01-01" }?.isSelectedByDefault, false)
    }

    func testTrashItemsAreDeletedPermanently() throws {
        try sandbox.makeFile(".Trash/old.zip", bytes: 8_000)
        let items = scanner.scan(.trash)
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].removalTarget.forcePermanent)
    }

    func testMissingFoldersYieldNothing() {
        XCTAssertTrue(scanner.scan(.developerCaches).isEmpty)
        XCTAssertTrue(scanner.scan(.mailAttachments).isEmpty)
    }

    func testEveryCatalogTargetPassesTheSafetyGuard() throws {
        // Build one item for every target and make sure the guard would let us remove it.
        let catalog = JunkCatalog(home: sandbox.root, systemLibrary: sandbox.url("SystemLibrary"))
        let safety = SafetyGuard(homeDirectory: sandbox.root)
        for category in ScanCategory.allCases {
            for target in catalog.targets(for: category) {
                try sandbox.makeFolder(String(target.url.path.dropFirst(sandbox.root.path.count + 1)))
                let item: URL
                let root: URL
                switch target.mode {
                case .contents:
                    item = target.url.appendingPathComponent("child")
                    root = target.url
                case .wholeFolder:
                    item = target.url
                    root = target.url.deletingLastPathComponent()
                }
                XCTAssertEqual(safety.check(item, allowedRoot: root), .allowed, "\(category) \(target.url.path)")
            }
        }
    }
}

final class DirectorySizerTests: XCTestCase {
    func testSumsNestedFilesAndIgnoresSymlinks() throws {
        let sandbox = try Sandbox()
        try sandbox.makeFile("folder/a", bytes: 10_000)
        try sandbox.makeFile("folder/sub/b", bytes: 20_000)
        try FileManager.default.createSymbolicLink(at: sandbox.url("folder/link"), withDestinationURL: sandbox.url("folder/a"))
        let size = DirectorySizer.size(of: sandbox.url("folder"))
        XCTAssertGreaterThanOrEqual(size, 30_000)
        XCTAssertLessThan(size, 60_000)
        XCTAssertEqual(DirectorySizer.size(of: sandbox.url("folder/link")), 0)
    }
}

final class FileFinderTests: XCTestCase {
    func testLargeFileFinderHonoursSizeAndSkipsLibrary() throws {
        let sandbox = try Sandbox()
        try sandbox.makeFile("Movies/big.mov", bytes: 300_000)
        try sandbox.makeFile("Documents/small.txt", bytes: 1_000)
        try sandbox.makeFile("Library/Caches/huge.bin", bytes: 400_000)
        try sandbox.makeFile(".hidden/huge.bin", bytes: 400_000)

        let finder = LargeFileFinder(home: sandbox.root)
        let found = finder.scan(root: sandbox.root, options: .init(minimumSize: 100_000))
        XCTAssertEqual(found.map(\.name), ["big.mov"])
        XCTAssertEqual(found.first?.kind, .video)
    }

    func testLargeFileFinderAgeFilter() throws {
        let sandbox = try Sandbox()
        let file = try sandbox.makeFile("old.zip", bytes: 200_000)
        let longAgo = Date().addingTimeInterval(-400 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: longAgo], ofItemAtPath: file.path)
        try sandbox.makeFile("new.zip", bytes: 200_000)

        let finder = LargeFileFinder(home: sandbox.root)
        let found = finder.scan(root: sandbox.root, options: .init(minimumSize: 100_000, unusedForDays: 365))
        // Access dates can be refreshed by the file system, so only assert the recent file is excluded.
        XCTAssertFalse(found.contains { $0.name == "new.zip" })
    }

    func testDuplicateFinderGroupsIdenticalContentOnly() throws {
        let sandbox = try Sandbox()
        try sandbox.makeFile("a/photo.jpg", bytes: 50_000, fill: 1)
        try sandbox.makeFile("b/photo copy.jpg", bytes: 50_000, fill: 1)
        try sandbox.makeFile("c/other.jpg", bytes: 50_000, fill: 2)
        try sandbox.makeFile("d/tiny.txt", bytes: 10, fill: 1)

        let groups = DuplicateFinder(home: sandbox.root).scan(root: sandbox.root, minimumSize: 1_000)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].files.map(\.name)), ["photo.jpg", "photo copy.jpg"])
        XCTAssertEqual(groups[0].wastedBytes, groups[0].fileSize)
    }

    func testFileKinds() {
        XCTAssertEqual(FileKind.from(pathExtension: "MOV"), .video)
        XCTAssertEqual(FileKind.from(pathExtension: "dmg"), .diskImage)
        XCTAssertEqual(FileKind.from(pathExtension: "zip"), .archive)
        XCTAssertEqual(FileKind.from(pathExtension: "xyz"), .other)
    }

    func testSpaceAnalyzerSortsChildrenBySize() async throws {
        let sandbox = try Sandbox()
        try sandbox.makeFile("big/file", bytes: 100_000)
        try sandbox.makeFile("small/file", bytes: 5_000)
        try sandbox.makeFile("loose.bin", bytes: 20_000)
        try sandbox.makeFolder("empty")

        let nodes = await SpaceAnalyzer().children(of: sandbox.root)
        XCTAssertEqual(nodes.map(\.name), ["big", "loose.bin", "small"])
        XCTAssertEqual(nodes.first?.isFolder, true)
        XCTAssertEqual(nodes.first { $0.name == "loose.bin" }?.isFolder, false)
    }
}

final class TreemapLayoutTests: XCTestCase {
    func testRectanglesFillTheAreaWithoutOverlapping() {
        let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)
        let values: [Double] = [60, 60, 40, 30, 20, 20, 10, 5, 3, 1]
        let rects = TreemapLayout.squarify(values, in: bounds)
        XCTAssertEqual(rects.count, values.count)

        let totalArea = rects.reduce(0.0) { $0 + Double($1.width * $1.height) }
        XCTAssertEqual(totalArea, Double(bounds.width * bounds.height), accuracy: 1)

        for (index, rect) in rects.enumerated() {
            let expected = values[index] / values.reduce(0, +) * Double(bounds.width * bounds.height)
            XCTAssertEqual(Double(rect.width * rect.height), expected, accuracy: 1)
            XCTAssertTrue(bounds.insetBy(dx: -0.5, dy: -0.5).contains(rect), "\(rect) escapes bounds")
            for other in rects[(index + 1)...] {
                let overlap = rect.intersection(other)
                XCTAssertTrue(overlap.isNull || overlap.width * overlap.height < 0.5)
            }
        }
    }

    func testDegenerateInputs() {
        XCTAssertEqual(TreemapLayout.squarify([], in: CGRect(x: 0, y: 0, width: 10, height: 10)), [])
        XCTAssertEqual(TreemapLayout.squarify([1, 2], in: .zero), [.zero, .zero])
        XCTAssertEqual(TreemapLayout.squarify([0, 0], in: CGRect(x: 0, y: 0, width: 10, height: 10)), [.zero, .zero])
    }
}
