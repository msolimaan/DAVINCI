import Foundation

/// Finds big and forgotten files, like CleanMyMac's "Large & Old Files".
public struct LargeFileFinder: Sendable {
    public struct Options: Sendable {
        public var minimumSize: Int64
        /// Only report files not opened or modified for this many days. nil reports everything.
        public var unusedForDays: Int?
        /// ~/Library is skipped by default; its contents are handled by the junk cleaners.
        public var skipsLibrary: Bool

        public init(minimumSize: Int64 = 100 * 1_000_000, unusedForDays: Int? = nil, skipsLibrary: Bool = true) {
            self.minimumSize = minimumSize
            self.unusedForDays = unusedForDays
            self.skipsLibrary = skipsLibrary
        }
    }

    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    /// Matching files, largest first. `progress` receives the number of files inspected so far.
    public func scan(
        root: URL,
        options: Options = Options(),
        now: Date = Date(),
        progress: (@Sendable (Int) -> Void)? = nil
    ) -> [FileEntry] {
        let skipped = options.skipsLibrary ? [home.appendingPathComponent("Library")] : []
        let walker = FileWalker(root: root, skippedFolders: skipped)
        let cutoff = options.unusedForDays.map { now.addingTimeInterval(-Double($0) * 86_400) }

        var results: [FileEntry] = []
        var inspected = 0
        walker.walk { entry in
            inspected += 1
            if inspected % 500 == 0 { progress?(inspected) }
            guard entry.size >= options.minimumSize else { return true }
            if let cutoff, let activity = entry.lastActivity, activity > cutoff { return true }
            results.append(entry)
            return true
        }
        progress?(inspected)
        return results.sorted { $0.size > $1.size }
    }
}
