import Foundation

/// Walks a folder tree and reports user files, treating packages (apps, photo libraries…) as single files.
struct FileWalker {
    static let keys: [URLResourceKey] = [
        .isDirectoryKey,
        .isPackageKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .contentAccessDateKey,
    ]

    /// Media libraries are never offered for deletion as a single file; Space Lens shows them instead.
    static let libraryPackageExtensions: Set<String> = [
        "photoslibrary", "photolibrary", "migratedphotolibrary", "aplibrary",
        "musiclibrary", "tvlibrary", "imovielibrary", "fcpbundle", "theater",
    ]

    let root: URL
    /// Folders that are never descended into (for example ~/Library, which has its own cleaners).
    let skippedFolders: Set<String>
    let includePackages: Bool

    init(root: URL, skippedFolders: [URL] = [], includePackages: Bool = true) {
        self.root = root
        self.skippedFolders = Set(skippedFolders.map { $0.standardizedFileURL.path })
        self.includePackages = includePackages
    }

    /// Calls `visit` for every file. Return false from `visit` to stop early.
    func walk(_ visit: (FileEntry) -> Bool) {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Self.keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return }

        for case let url as URL in enumerator {
            if Task.isCancelled { return }
            guard let values = try? url.resourceValues(forKeys: Set(Self.keys)) else { continue }
            if values.isSymbolicLink == true { continue }

            if values.isDirectory == true {
                if skippedFolders.contains(url.standardizedFileURL.path) {
                    enumerator.skipDescendants()
                    continue
                }
                guard values.isPackage == true, includePackages else { continue }
                if Self.libraryPackageExtensions.contains(url.pathExtension.lowercased()) { continue }
                let entry = FileEntry(
                    url: url,
                    size: DirectorySizer.size(of: url),
                    modified: values.contentModificationDate,
                    lastOpened: values.contentAccessDate
                )
                if !visit(entry) { return }
                continue
            }

            guard values.isRegularFile == true else { continue }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
            let entry = FileEntry(
                url: url,
                size: size,
                modified: values.contentModificationDate,
                lastOpened: values.contentAccessDate
            )
            if !visit(entry) { return }
        }
    }
}
