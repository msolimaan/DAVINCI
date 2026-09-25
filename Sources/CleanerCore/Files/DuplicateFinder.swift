import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

public struct DuplicateGroup: Identifiable, Sendable {
    public let id: String
    /// Identical files, oldest first (the oldest is usually the original).
    public let files: [FileEntry]

    public init(id: String, files: [FileEntry]) {
        self.id = id
        self.files = files
    }

    public var fileSize: Int64 { files.first?.size ?? 0 }
    /// Space that would be freed by keeping a single copy.
    public var wastedBytes: Int64 { fileSize * Int64(max(0, files.count - 1)) }
}

/// Finds files with identical content: group by size, then by a hash of the first 64 KB, then by a full hash.
public struct DuplicateFinder: Sendable {
    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public func scan(
        root: URL,
        minimumSize: Int64 = 1_000_000,
        progress: (@Sendable (String) -> Void)? = nil
    ) -> [DuplicateGroup] {
        progress?("Collecting files…")
        var bySize: [Int64: [FileEntry]] = [:]
        FileWalker(
            root: root,
            skippedFolders: [home.appendingPathComponent("Library")],
            includePackages: false
        ).walk { entry in
            if entry.size >= minimumSize {
                bySize[entry.size, default: []].append(entry)
            }
            return true
        }

        let candidates = bySize.values.filter { $0.count > 1 }
        var groups: [DuplicateGroup] = []
        for (index, sameSize) in candidates.enumerated() {
            if Task.isCancelled { break }
            progress?("Comparing \(index + 1) of \(candidates.count)…")

            let byPrefix = Dictionary(grouping: sameSize) { FileHasher.hash($0.url, limit: 64 * 1024) ?? UUID().uuidString }
            for prefixGroup in byPrefix.values where prefixGroup.count > 1 {
                let byContent = Dictionary(grouping: prefixGroup) { FileHasher.hash($0.url) ?? UUID().uuidString }
                for (hash, files) in byContent where files.count > 1 {
                    let ordered = files.sorted {
                        ($0.modified ?? .distantFuture) < ($1.modified ?? .distantFuture)
                    }
                    groups.append(DuplicateGroup(id: hash, files: ordered))
                }
            }
        }
        return groups.sorted { $0.wastedBytes > $1.wastedBytes }
    }
}

enum FileHasher {
    /// Hex digest of the file (or of its first `limit` bytes). SHA-256 on macOS.
    static func hash(_ url: URL, limit: Int? = nil) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        #if canImport(CryptoKit)
        var hasher = SHA256()
        #else
        var hasher = FNV1a()
        #endif
        var remaining = limit ?? Int.max
        while remaining > 0 {
            if Task.isCancelled { return nil }
            let chunkSize = min(1 << 20, remaining)
            guard let data = try? handle.read(upToCount: chunkSize), !data.isEmpty else { break }
            hasher.update(data: data)
            remaining -= data.count
        }
        #if canImport(CryptoKit)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        #else
        return hasher.hexDigest
        #endif
    }
}

#if !canImport(CryptoKit)
/// Portable fallback so the engine also builds on Linux (used only by tests there).
struct FNV1a {
    private var value: UInt64 = 0xcbf2_9ce4_8422_2325

    mutating func update(data: Data) {
        for byte in data {
            value ^= UInt64(byte)
            value = value &* 0x0000_0100_0000_01b3
        }
    }

    var hexDigest: String { String(value, radix: 16) }
}
#endif
