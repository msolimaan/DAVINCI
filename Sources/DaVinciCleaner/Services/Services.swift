import AppKit
import CleanerCore
import Foundation

/// Runs blocking work off the main thread. Unlike `Task.detached`, cancelling the calling task
/// also cancels the work, so the "Stop" buttons really stop scanning.
func runInBackground<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await withTaskGroup(of: T.self) { group in
        group.addTask { work() }
        return await group.next()!
    }
}

enum Preferences {
    static let removalModeKey = "removalMode"
    static let showMenuBarKey = "showMenuBarMonitor"

    static var removalMode: RemovalMode {
        let raw = UserDefaults.standard.string(forKey: removalModeKey) ?? RemovalMode.moveToTrash.rawValue
        return RemovalMode(rawValue: raw) ?? .moveToTrash
    }
}

enum FullDiskAccess {
    /// macOS doesn't offer an API for this, so try to open a file that only Full Disk Access unlocks.
    static var isGranted: Bool {
        let probes = [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            NSHomeDirectory() + "/Library/Safari/Bookmarks.plist",
            NSHomeDirectory() + "/Library/Containers/com.apple.stocks",
        ]
        for path in probes where FileManager.default.fileExists(atPath: path) {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                return (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
            }
            if let handle = FileHandle(forReadingAtPath: path) {
                try? handle.close()
                return true
            }
            return false
        }
        // Nothing to probe; assume access so we don't nag needlessly.
        return true
    }

    static func openSettings() {
        let link = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }
}

enum Finder {
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func emptyTrashURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
    }

    static func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// `~/Downloads/file.zip` instead of `/Users/name/Downloads/file.zip`.
    static func abbreviated(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    static func chooseFolder(startingAt url: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = url
        return panel.runModal() == .OK ? panel.url : nil
    }
}

extension RemovalReport {
    var summary: String {
        let freed = ByteFormatter.string(freedBytes)
        switch Preferences.removalMode {
        case .moveToTrash:
            return "\(removed.count) item\(removed.count == 1 ? "" : "s") moved to the Trash (\(freed)). Empty the Trash to get the space back."
        case .deletePermanently:
            return "\(removed.count) item\(removed.count == 1 ? "" : "s") removed, \(freed) freed."
        }
    }
}

extension Date {
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
