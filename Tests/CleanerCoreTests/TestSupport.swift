import Foundation
import XCTest

/// A throwaway folder tree that stands in for a home directory.
final class Sandbox {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DaVinciCleanerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func url(_ relative: String) -> URL {
        root.appendingPathComponent(relative)
    }

    @discardableResult
    func makeFolder(_ relative: String) throws -> URL {
        let url = self.url(relative)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    func makeFile(_ relative: String, bytes: Int = 4096, fill: UInt8 = 0x41) throws -> URL {
        let url = self.url(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: fill, count: bytes).write(to: url)
        return url
    }

    func makePlist(_ relative: String, _ contents: [String: Any]) throws {
        let url = self.url(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0)
        try data.write(to: url)
    }

    func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: url(relative).path)
    }
}
