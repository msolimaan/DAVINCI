import Foundation

/// Measures how much disk space files and folders really occupy.
public enum DirectorySizer {
    static let fileKeys: [URLResourceKey] = [
        .isRegularFileKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .fileSizeKey,
    ]

    /// Allocated size on disk of a file, or of everything inside a folder (including packages).
    /// Symbolic links count as zero because removing a link frees nothing.
    public static func size(of url: URL, fileManager: FileManager = .default) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
            return 0
        }
        if values.isSymbolicLink == true { return 0 }
        guard values.isDirectory == true else { return fileSize(of: url) }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: fileKeys,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if Task.isCancelled { break }
            total += fileSize(of: fileURL)
        }
        return total
    }

    public static func fileSize(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: Set(fileKeys)),
              values.isRegularFile == true else { return 0 }
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
    }
}
