import Foundation

/// Finds junk for each `ScanCategory` using the locations in a `JunkCatalog`.
public struct JunkScanner: Sendable {
    public let catalog: JunkCatalog

    public init(catalog: JunkCatalog = JunkCatalog()) {
        self.catalog = catalog
    }

    /// Items for one category, largest first. Empty items are dropped.
    public func scan(_ category: ScanCategory) -> [CleanupItem] {
        var items: [CleanupItem] = []
        for target in catalog.targets(for: category) {
            if Task.isCancelled { break }
            items += self.items(for: target)
        }
        return items
            .filter { $0.size > 0 }
            .sorted { $0.size > $1.size }
    }

    func items(for target: JunkTarget) -> [CleanupItem] {
        let fileManager = FileManager.default
        switch target.mode {
        case .wholeFolder(let label):
            guard fileManager.fileExists(atPath: target.url.path) else { return [] }
            return [
                CleanupItem(
                    url: target.url,
                    name: label,
                    size: DirectorySizer.size(of: target.url),
                    category: target.category,
                    allowedRoot: target.url.deletingLastPathComponent(),
                    isSelectedByDefault: target.selectedByDefault
                ),
            ]
        case .contents:
            guard let children = try? fileManager.contentsOfDirectory(
                at: target.url,
                includingPropertiesForKeys: nil,
                options: []
            ) else { return [] }

            var items: [CleanupItem] = []
            for child in children {
                if Task.isCancelled { break }
                let name = child.lastPathComponent
                if target.excludedNames.contains(name) || name == ".DS_Store" || name == ".localized" {
                    continue
                }
                items.append(
                    CleanupItem(
                        url: child,
                        name: name,
                        size: DirectorySizer.size(of: child),
                        category: target.category,
                        allowedRoot: target.url,
                        isSelectedByDefault: target.selectedByDefault
                    )
                )
            }
            return items
        }
    }
}
