import Foundation

/// The last line of defence before anything is deleted.
///
/// Every removal goes through `check(_:allowedRoot:)`. An item is only allowed when it sits
/// strictly inside the folder its scanner was responsible for, and never inside a
/// macOS system location or on top of an important folder in your home directory.
public struct SafetyGuard: Sendable {
    public enum Verdict: Equatable, Sendable {
        case allowed
        case denied(String)

        public var isAllowed: Bool { self == .allowed }
    }

    /// System locations that are never touched, whatever a scanner reports.
    public static let protectedSystemPaths: [String] = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
        "/etc",
        "/private/etc",
        "/var/db",
        "/private/var/db",
        "/var/root",
        "/private/var/root",
        "/Library/Apple",
        "/Library/Keychains",
        "/Library/Security",
        "/dev",
        "/cores",
    ]

    /// Folders in the home directory that may hold removable things but must never be removed themselves.
    public static let protectedHomeFolders: [String] = [
        "Applications",
        "Desktop",
        "Documents",
        "Downloads",
        "Library",
        "Library/Application Support",
        "Library/Caches",
        "Library/Containers",
        "Library/Group Containers",
        "Library/Keychains",
        "Library/Logs",
        "Library/Mail",
        "Library/Messages",
        "Library/Mobile Documents",
        "Library/Preferences",
        "Movies",
        "Music",
        "Pictures",
        "Public",
        ".Trash",
        ".ssh",
        ".gnupg",
    ]

    /// Anything inside these home folders is never removed (credentials and message history).
    public static let sealedHomeFolders: [String] = [
        "Library/Keychains",
        "Library/Messages",
        ".ssh",
        ".gnupg",
    ]

    public let homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    public func check(_ url: URL, allowedRoot: URL) -> Verdict {
        let path = Self.normalizedPath(url, resolveLastComponent: false)
        let root = Self.normalizedPath(allowedRoot, resolveLastComponent: true)
        let home = Self.normalizedPath(homeDirectory, resolveLastComponent: true)

        if path == "/" || path.isEmpty {
            return .denied("Refusing to remove the root of the disk.")
        }
        if path == home {
            return .denied("Refusing to remove your home folder.")
        }
        for protected in Self.protectedSystemPaths where Self.isSameOrInside(path, protected) {
            return .denied("\(protected) is protected by macOS.")
        }
        for folder in Self.protectedHomeFolders where path == home + "/" + folder {
            return .denied("~/\(folder) is an essential folder and is never removed.")
        }
        for folder in Self.sealedHomeFolders where Self.isSameOrInside(path, home + "/" + folder) {
            return .denied("~/\(folder) holds private data and is never touched.")
        }
        guard Self.isStrictlyInside(path, root) else {
            return .denied("\(url.path) is outside of \(allowedRoot.path).")
        }
        return .allowed
    }

    // MARK: - Path helpers

    /// Standardises a path and resolves symlinks in its parent folders.
    ///
    /// The last component is resolved only on request: removing a symlink removes the link,
    /// not whatever it points to, so the link's own location is what matters.
    static func normalizedPath(_ url: URL, resolveLastComponent: Bool) -> String {
        let standardized = url.standardizedFileURL
        let resolved: URL
        if resolveLastComponent {
            resolved = standardized.resolvingSymlinksInPath()
        } else {
            let parent = standardized.deletingLastPathComponent().resolvingSymlinksInPath()
            resolved = parent.appendingPathComponent(standardized.lastPathComponent)
        }
        var path = resolved.path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    static func isSameOrInside(_ path: String, _ folder: String) -> Bool {
        path == folder || path.hasPrefix(folder + "/")
    }

    static func isStrictlyInside(_ path: String, _ folder: String) -> Bool {
        if folder == "/" { return path.count > 1 }
        return path.hasPrefix(folder + "/")
    }
}
