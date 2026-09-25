import Foundation

/// A single removable thing found by a junk scan: usually a folder of caches or a log file.
public struct CleanupItem: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let size: Int64
    public let category: ScanCategory
    /// The folder this item must live inside; checked again right before removal.
    public let allowedRoot: URL
    public let isSelectedByDefault: Bool

    public init(
        url: URL,
        name: String,
        size: Int64,
        category: ScanCategory,
        allowedRoot: URL,
        isSelectedByDefault: Bool = true
    ) {
        self.url = url
        self.name = name
        self.size = size
        self.category = category
        self.allowedRoot = allowedRoot
        self.isSelectedByDefault = isSelectedByDefault
    }

    public var removalTarget: RemovalTarget {
        RemovalTarget(
            url: url,
            allowedRoot: allowedRoot,
            size: size,
            forcePermanent: category.alwaysDeletesPermanently
        )
    }
}

public enum ByteFormatter {
    public static func string(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = .useAll
        return formatter.string(fromByteCount: bytes)
    }
}
