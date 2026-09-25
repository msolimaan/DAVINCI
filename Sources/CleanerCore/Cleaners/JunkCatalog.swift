import Foundation

/// A place on disk where junk of one category accumulates.
public struct JunkTarget: Sendable {
    public enum Mode: Sendable {
        /// Every item inside the folder is a separate removable item; the folder itself stays.
        case contents
        /// The folder is removed as a whole (the owning tool recreates it on demand).
        case wholeFolder(label: String)
    }

    public let category: ScanCategory
    public let url: URL
    public let mode: Mode
    public let excludedNames: Set<String>
    public let selectedByDefault: Bool

    public init(
        category: ScanCategory,
        url: URL,
        mode: Mode,
        excludedNames: Set<String> = [],
        selectedByDefault: Bool = true
    ) {
        self.category = category
        self.url = url
        self.mode = mode
        self.excludedNames = excludedNames
        self.selectedByDefault = selectedByDefault
    }
}

/// The curated list of junk locations, modelled on what CleanMyMac, Mole and PureMac clean.
public struct JunkCatalog: Sendable {
    public let home: URL
    public let systemLibrary: URL

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemLibrary: URL = URL(fileURLWithPath: "/Library")
    ) {
        self.home = home
        self.systemLibrary = systemLibrary
    }

    private func homePath(_ relative: String) -> URL {
        home.appendingPathComponent(relative, isDirectory: true)
    }

    /// Cache folders that belong to other categories, or that hold state rather than disposable cache.
    public static let userCacheExclusions: Set<String> = [
        // Claimed by the browser category.
        "com.apple.Safari", "Google", "Firefox", "Mozilla", "Microsoft Edge", "BraveSoftware",
        "company.thebrowser.Browser", "com.operasoftware.Opera",
        // Claimed by the Xcode and developer categories.
        "com.apple.dt.Xcode", "Homebrew", "pip", "Yarn", "CocoaPods", "org.swift.swiftpm",
        // Hold sync or account state rather than disposable cache.
        "CloudKit", "com.apple.bird", "com.apple.akd", "com.apple.nsurlsessiond",
        "com.apple.containermanagerd", "FamilyCircle", "com.apple.HomeKit",
        "com.apple.ap.adprivacyd", "com.apple.findmy.fmipcore",
        // Ourselves.
        "com.davinci.cleaner",
        // Finder metadata.
        ".DS_Store", ".localized",
    ]

    public func targets(for category: ScanCategory) -> [JunkTarget] {
        switch category {
        case .userCaches:
            return [
                JunkTarget(
                    category: category,
                    url: homePath("Library/Caches"),
                    mode: .contents,
                    excludedNames: Self.userCacheExclusions
                ),
            ]
        case .userLogs:
            return [
                JunkTarget(category: category, url: homePath("Library/Logs"), mode: .contents),
            ]
        case .systemLogs:
            return [
                JunkTarget(
                    category: category,
                    url: systemLibrary.appendingPathComponent("Logs", isDirectory: true),
                    mode: .contents
                ),
            ]
        case .xcodeJunk:
            return [
                JunkTarget(category: category, url: homePath("Library/Developer/Xcode/DerivedData"), mode: .contents),
                JunkTarget(category: category, url: homePath("Library/Developer/Xcode/iOS DeviceSupport"), mode: .contents),
                JunkTarget(category: category, url: homePath("Library/Developer/Xcode/watchOS DeviceSupport"), mode: .contents),
                JunkTarget(category: category, url: homePath("Library/Developer/Xcode/tvOS DeviceSupport"), mode: .contents),
                JunkTarget(category: category, url: homePath("Library/Developer/CoreSimulator/Caches"), mode: .contents),
                JunkTarget(
                    category: category,
                    url: homePath("Library/Caches/com.apple.dt.Xcode"),
                    mode: .wholeFolder(label: "Xcode Cache")
                ),
                // Archives contain the dSYMs needed to symbolicate crash reports, so they are opt-in.
                JunkTarget(
                    category: category,
                    url: homePath("Library/Developer/Xcode/Archives"),
                    mode: .contents,
                    selectedByDefault: false
                ),
            ]
        case .developerCaches:
            return [
                JunkTarget(category: category, url: homePath("Library/Caches/Homebrew"), mode: .wholeFolder(label: "Homebrew Downloads")),
                JunkTarget(category: category, url: homePath(".npm/_cacache"), mode: .wholeFolder(label: "npm Cache")),
                JunkTarget(category: category, url: homePath("Library/Caches/Yarn"), mode: .wholeFolder(label: "Yarn Cache")),
                JunkTarget(category: category, url: homePath("Library/pnpm/store"), mode: .wholeFolder(label: "pnpm Store")),
                JunkTarget(category: category, url: homePath("Library/Caches/pip"), mode: .wholeFolder(label: "pip Cache")),
                JunkTarget(category: category, url: homePath("Library/Caches/CocoaPods"), mode: .wholeFolder(label: "CocoaPods Cache")),
                JunkTarget(category: category, url: homePath("Library/Caches/org.swift.swiftpm"), mode: .wholeFolder(label: "Swift Package Cache")),
                JunkTarget(category: category, url: homePath(".gradle/caches"), mode: .wholeFolder(label: "Gradle Cache")),
                JunkTarget(category: category, url: homePath(".cargo/registry/cache"), mode: .wholeFolder(label: "Cargo Registry Cache")),
                JunkTarget(category: category, url: homePath("go/pkg/mod/cache/download"), mode: .wholeFolder(label: "Go Module Cache")),
            ]
        case .browserCaches:
            return [
                JunkTarget(category: category, url: homePath("Library/Caches/com.apple.Safari"), mode: .wholeFolder(label: "Safari")),
                JunkTarget(category: category, url: homePath("Library/Caches/Google/Chrome"), mode: .wholeFolder(label: "Google Chrome")),
                JunkTarget(category: category, url: homePath("Library/Caches/Firefox/Profiles"), mode: .wholeFolder(label: "Firefox")),
                JunkTarget(category: category, url: homePath("Library/Caches/Microsoft Edge"), mode: .wholeFolder(label: "Microsoft Edge")),
                JunkTarget(category: category, url: homePath("Library/Caches/BraveSoftware/Brave-Browser"), mode: .wholeFolder(label: "Brave")),
                JunkTarget(category: category, url: homePath("Library/Caches/company.thebrowser.Browser"), mode: .wholeFolder(label: "Arc")),
                JunkTarget(category: category, url: homePath("Library/Caches/com.operasoftware.Opera"), mode: .wholeFolder(label: "Opera")),
            ]
        case .mailAttachments:
            return [
                JunkTarget(
                    category: category,
                    url: homePath("Library/Containers/com.apple.mail/Data/Library/Mail Downloads"),
                    mode: .contents
                ),
            ]
        case .trash:
            return [
                JunkTarget(category: category, url: homePath(".Trash"), mode: .contents),
            ]
        }
    }
}
