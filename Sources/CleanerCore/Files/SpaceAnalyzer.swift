import Foundation

/// One box in Space Lens: a file or folder with its total size.
public struct SpaceNode: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let size: Int64
    public let isFolder: Bool
    public let itemCount: Int

    public init(url: URL, size: Int64, isFolder: Bool, itemCount: Int) {
        self.url = url
        self.size = size
        self.isFolder = isFolder
        self.itemCount = itemCount
    }

    public var name: String { url.lastPathComponent }
}

/// Measures the immediate children of a folder so Space Lens can draw them and drill down.
public struct SpaceAnalyzer: Sendable {
    public init() {}

    /// Children of `folder`, largest first. Packages count as files. Sizes are measured concurrently.
    public func children(of folder: URL) async -> [SpaceNode] {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey],
            options: []
        ) else { return [] }

        return await withTaskGroup(of: SpaceNode?.self) { group in
            for url in urls {
                group.addTask {
                    guard !Task.isCancelled,
                          let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]),
                          values.isSymbolicLink != true else { return nil }
                    let isFolder = values.isDirectory == true && values.isPackage != true
                    let count = isFolder
                        ? ((try? fileManager.contentsOfDirectory(atPath: url.path).count) ?? 0)
                        : 0
                    let size = DirectorySizer.size(of: url)
                    guard size > 0 else { return nil }
                    return SpaceNode(url: url, size: size, isFolder: isFolder, itemCount: count)
                }
            }
            var nodes: [SpaceNode] = []
            for await node in group {
                if let node { nodes.append(node) }
            }
            return nodes.sorted { $0.size > $1.size }
        }
    }
}
