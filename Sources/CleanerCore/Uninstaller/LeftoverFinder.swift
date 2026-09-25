import Foundation

/// A file or folder an app left behind in a Library folder.
public struct LeftoverFile: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    /// Human readable location, e.g. "Caches" or "Launch Daemons".
    public let location: String
    public let size: Int64
    public let allowedRoot: URL
    /// Lives in /Library, so removing it needs administrator rights.
    public let isSystemWide: Bool

    public var removalTarget: RemovalTarget {
        RemovalTarget(url: url, allowedRoot: allowedRoot, size: size)
    }
}

/// Finds the support files an app spreads around ~/Library and /Library, the way Pearcleaner and AppCleaner do.
public struct LeftoverFinder: Sendable {
    public struct Location: Sendable {
        public let name: String
        public let url: URL
        public let isSystemWide: Bool
    }

    public let locations: [Location]

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemLibrary: URL = URL(fileURLWithPath: "/Library")
    ) {
        let userLibrary = home.appendingPathComponent("Library", isDirectory: true)
        let user: [(String, String)] = [
            ("Application Support", "Application Support"),
            ("Caches", "Caches"),
            ("Preferences", "Preferences"),
            ("Preferences (By Host)", "Preferences/ByHost"),
            ("Containers", "Containers"),
            ("Group Containers", "Group Containers"),
            ("Application Scripts", "Application Scripts"),
            ("Saved Application State", "Saved Application State"),
            ("Launch Agents", "LaunchAgents"),
            ("HTTP Storage", "HTTPStorages"),
            ("WebKit Data", "WebKit"),
            ("Cookies", "Cookies"),
            ("Logs", "Logs"),
            ("Internet Plug-Ins", "Internet Plug-Ins"),
        ]
        let system: [(String, String)] = [
            ("System Application Support", "Application Support"),
            ("System Caches", "Caches"),
            ("System Preferences", "Preferences"),
            ("System Launch Agents", "LaunchAgents"),
            ("Launch Daemons", "LaunchDaemons"),
            ("Privileged Helpers", "PrivilegedHelperTools"),
            ("System Logs", "Logs"),
        ]
        locations =
            user.map { Location(name: $0.0, url: userLibrary.appendingPathComponent($0.1, isDirectory: true), isSystemWide: false) }
            + system.map { Location(name: $0.0, url: systemLibrary.appendingPathComponent($0.1, isDirectory: true), isSystemWide: true) }
    }

    public func leftovers(for app: InstalledApp) -> [LeftoverFile] {
        leftovers(bundleIdentifier: app.bundleIdentifier, appName: app.name)
    }

    public func leftovers(bundleIdentifier: String, appName: String) -> [LeftoverFile] {
        scan { name in Self.matches(name, bundleIdentifier: bundleIdentifier, appName: appName) }
    }

    /// Leftovers whose bundle identifier doesn't belong to any installed app.
    /// `isInstalled` lets the caller consult Launch Services for apps outside /Applications.
    public func orphans(
        installedBundleIdentifiers: Set<String>,
        isInstalled: @Sendable (String) -> Bool = { _ in false }
    ) -> [LeftoverFile] {
        let installed = installedBundleIdentifiers.map { $0.lowercased() }
        return scan { name in
            guard let identifier = Self.bundleIdentifierCandidate(from: name) else { return false }
            if Self.isSystemIdentifier(identifier) { return false }
            let belongsToInstalledApp = installed.contains { id in
                identifier == id || identifier.hasPrefix(id + ".") || id.hasPrefix(identifier + ".")
            }
            return !belongsToInstalledApp && !isInstalled(identifier)
        }
        .filter { !$0.isSystemWide }
    }

    private func scan(_ predicate: (String) -> Bool) -> [LeftoverFile] {
        let fileManager = FileManager.default
        var results: [LeftoverFile] = []
        for location in locations {
            guard let children = try? fileManager.contentsOfDirectory(
                at: location.url,
                includingPropertiesForKeys: nil,
                options: []
            ) else { continue }
            for child in children where predicate(child.lastPathComponent) {
                results.append(
                    LeftoverFile(
                        url: child,
                        location: location.name,
                        size: DirectorySizer.size(of: child),
                        allowedRoot: location.url,
                        isSystemWide: location.isSystemWide
                    )
                )
            }
        }
        return results.sorted { $0.size > $1.size }
    }

    // MARK: - Matching

    /// Whether a file name in a Library folder belongs to the app.
    ///
    /// Matches `com.vendor.app`, `com.vendor.app.plist`, `com.vendor.app.savedState`,
    /// `group.com.vendor.app`, `TEAMID.com.vendor.app.shared` and a folder named exactly like the app.
    public static func matches(_ fileName: String, bundleIdentifier: String, appName: String) -> Bool {
        let name = fileName.lowercased()
        let identifier = bundleIdentifier.lowercased()
        if !identifier.isEmpty {
            if name == identifier
                || name.hasPrefix(identifier + ".")
                || name.hasSuffix("." + identifier)
                || name.contains("." + identifier + ".") {
                return true
            }
        }
        // Name matching is exact and skips very short names, which are too generic to trust.
        let appName = appName.lowercased().trimmingCharacters(in: .whitespaces)
        guard appName.count >= 4 else { return false }
        let stripped = name.hasSuffix(".plist") ? String(name.dropLast(".plist".count)) : name
        return stripped == appName
    }

    /// Turns `com.vendor.app.plist` or `com.vendor.app.savedState` into `com.vendor.app`, or nil if the
    /// name doesn't look like a reverse-DNS identifier.
    static func bundleIdentifierCandidate(from fileName: String) -> String? {
        var name = fileName.lowercased()
        for suffix in [".plist", ".savedstate", ".binarycookies"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard parts.allSatisfy({ $0.unicodeScalars.allSatisfy(allowed.contains) }) else { return nil }
        guard ["com", "org", "net", "io", "de", "co", "app", "dev", "me", "ru", "jp", "uk"].contains(String(parts[0])) else {
            return nil
        }
        return name
    }

    static func isSystemIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix("com.apple.")
            || identifier.hasPrefix("group.com.apple.")
            || identifier.hasPrefix("com.davinci.cleaner")
    }
}
