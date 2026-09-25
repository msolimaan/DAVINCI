import Foundation

public struct InstalledApp: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let bundleIdentifier: String
    public let version: String?
    public var size: Int64
    public let lastUsed: Date?

    public init(url: URL, name: String, bundleIdentifier: String, version: String?, size: Int64, lastUsed: Date?) {
        self.url = url
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.size = size
        self.lastUsed = lastUsed
    }

    public var isAppleApp: Bool { bundleIdentifier.hasPrefix("com.apple.") }
}

/// Lists the apps installed in /Applications and ~/Applications.
public struct AppInventory: Sendable {
    public let searchRoots: [URL]
    public let ownBundleIdentifier: String

    public init(searchRoots: [URL]? = nil, ownBundleIdentifier: String = "com.davinci.cleaner") {
        self.searchRoots = searchRoots ?? [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]
        self.ownBundleIdentifier = ownBundleIdentifier
    }

    /// Apps sorted by name. Apple apps are skipped because macOS reinstalls or protects them.
    /// Sizes are left at zero when `computeSizes` is false so the list can appear instantly.
    public func loadApps(includeAppleApps: Bool = false, computeSizes: Bool = false) -> [InstalledApp] {
        var apps: [InstalledApp] = []
        var seen = Set<String>()
        for bundleURL in appBundleURLs() {
            guard let app = Self.readApp(at: bundleURL, computeSize: computeSizes) else { continue }
            if app.bundleIdentifier == ownBundleIdentifier { continue }
            if app.isAppleApp && !includeAppleApps { continue }
            if seen.insert(app.url.path).inserted {
                apps.append(app)
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// `.app` bundles in the search roots, including one level of sub-folders (e.g. /Applications/Adobe Photoshop 2025/).
    func appBundleURLs() -> [URL] {
        let fileManager = FileManager.default
        var result: [URL] = []
        for root in searchRoots {
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for child in children {
                if child.pathExtension == "app" {
                    result.append(child)
                } else if (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                          let nested = try? fileManager.contentsOfDirectory(
                              at: child,
                              includingPropertiesForKeys: nil,
                              options: [.skipsHiddenFiles]
                          ) {
                    result += nested.filter { $0.pathExtension == "app" }
                }
            }
        }
        return result
    }

    public static func readApp(at url: URL, computeSize: Bool) -> InstalledApp? {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleIdentifier = plist["CFBundleIdentifier"] as? String,
              !bundleIdentifier.isEmpty else { return nil }

        let fileName = url.deletingPathExtension().lastPathComponent
        let name = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? fileName
        let version = (plist["CFBundleShortVersionString"] as? String) ?? (plist["CFBundleVersion"] as? String)
        let lastUsed = try? url.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate

        return InstalledApp(
            url: url,
            name: name.isEmpty ? fileName : name,
            bundleIdentifier: bundleIdentifier,
            version: version,
            size: computeSize ? DirectorySizer.size(of: url) : 0,
            lastUsed: lastUsed
        )
    }
}
