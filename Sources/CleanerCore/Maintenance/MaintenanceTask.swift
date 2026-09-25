import Foundation

/// A one-click maintenance or troubleshooting script, like CleanMyMac's "Maintenance" module or OnyX.
public struct MaintenanceTask: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    public let whenToUse: String
    public let symbolName: String
    public let command: String
    public let requiresAdministrator: Bool
    public let isRecommended: Bool

    public static let all: [MaintenanceTask] = [
        MaintenanceTask(
            id: "free-ram",
            title: "Free Up RAM",
            summary: "Clears inactive memory and disk caches so apps get memory back immediately.",
            whenToUse: "Your Mac feels sluggish or Memory Pressure is yellow or red.",
            symbolName: "memorychip",
            command: "/usr/sbin/purge",
            requiresAdministrator: true,
            isRecommended: true
        ),
        MaintenanceTask(
            id: "flush-dns",
            title: "Flush DNS Cache",
            summary: "Forgets cached website addresses so they are looked up fresh.",
            whenToUse: "Websites won't load, or load an old version after a server move.",
            symbolName: "network",
            command: "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder",
            requiresAdministrator: true,
            isRecommended: true
        ),
        MaintenanceTask(
            id: "maintenance-scripts",
            title: "Run Maintenance Scripts",
            summary: "Runs the daily, weekly and monthly housekeeping scripts that rotate logs and clean temporary files.",
            whenToUse: "Your Mac is usually asleep at night, when macOS would run them itself.",
            symbolName: "wrench.and.screwdriver",
            command: "if [ -x /usr/sbin/periodic ]; then /usr/sbin/periodic daily weekly monthly; fi",
            requiresAdministrator: true,
            isRecommended: true
        ),
        MaintenanceTask(
            id: "reindex-spotlight",
            title: "Reindex Spotlight",
            summary: "Rebuilds the Spotlight index of your startup disk. Indexing continues in the background.",
            whenToUse: "Spotlight or Mail search misses files, or shows ones that no longer exist.",
            symbolName: "magnifyingglass",
            command: "/usr/bin/mdutil -E /",
            requiresAdministrator: true,
            isRecommended: false
        ),
        MaintenanceTask(
            id: "thin-snapshots",
            title: "Thin Time Machine Snapshots",
            summary: "Asks macOS to release space held by local Time Machine snapshots.",
            whenToUse: "Finder shows much less free space than you expect.",
            symbolName: "clock.arrow.circlepath",
            command: "/usr/bin/tmutil thinlocalsnapshots / 999999999999 4",
            requiresAdministrator: true,
            isRecommended: false
        ),
        MaintenanceTask(
            id: "rebuild-launch-services",
            title: "Repair \"Open With\" Menu",
            summary: "Rebuilds the Launch Services database that decides which app opens which file.",
            whenToUse: "\"Open With\" shows duplicate or deleted apps, or files open in the wrong app.",
            symbolName: "square.stack.3d.up",
            command: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user",
            requiresAdministrator: false,
            isRecommended: false
        ),
        MaintenanceTask(
            id: "reset-quicklook",
            title: "Reset Quick Look",
            summary: "Clears Quick Look thumbnails and reloads its preview plug-ins.",
            whenToUse: "Space-bar previews or Finder thumbnails are blank or outdated.",
            symbolName: "eye",
            command: "/usr/bin/qlmanage -r cache >/dev/null 2>&1; /usr/bin/qlmanage -r",
            requiresAdministrator: false,
            isRecommended: true
        ),
        MaintenanceTask(
            id: "font-caches",
            title: "Clear Font Caches",
            summary: "Removes your font caches; macOS rebuilds them on next use.",
            whenToUse: "Text shows in the wrong font or with garbled characters.",
            symbolName: "textformat",
            command: "/usr/bin/atsutil databases -removeUser; /usr/bin/atsutil server -shutdown; /usr/bin/atsutil server -ping",
            requiresAdministrator: false,
            isRecommended: false
        ),
        MaintenanceTask(
            id: "restart-finder-dock",
            title: "Restart Finder & Dock",
            summary: "Relaunches Finder, the Dock and the menu bar.",
            whenToUse: "Finder, the Dock or Mission Control stopped responding.",
            symbolName: "dock.rectangle",
            command: "/usr/bin/killall Finder; /usr/bin/killall Dock; /usr/bin/killall SystemUIServer",
            requiresAdministrator: false,
            isRecommended: false
        ),
        MaintenanceTask(
            id: "verify-disk",
            title: "Verify Startup Disk",
            summary: "Checks the startup disk's file system for errors (read-only, safe while you work).",
            whenToUse: "You see disk errors, or apps crash while saving files.",
            symbolName: "internaldrive",
            command: "/usr/sbin/diskutil verifyVolume /",
            requiresAdministrator: false,
            isRecommended: false
        ),
    ]
}

/// Runs a set of tasks, asking for the administrator password only once for all tasks that need it.
public enum MaintenanceRunner {
    public enum Outcome: Equatable, Sendable {
        case succeeded
        case failed(String)
        case cancelled
    }

    public static func run(
        _ tasks: [MaintenanceTask],
        onUpdate: @escaping @Sendable (MaintenanceTask.ID, Outcome?) async -> Void
    ) async {
        let adminTasks = tasks.filter(\.requiresAdministrator)
        let userTasks = tasks.filter { !$0.requiresAdministrator }

        if !adminTasks.isEmpty {
            for task in adminTasks { await onUpdate(task.id, nil) }
            let result = await CommandRunner.run(batchedCommand(for: adminTasks), asAdministrator: true)
            let outcomes = parseBatchOutput(result, tasks: adminTasks)
            for task in adminTasks { await onUpdate(task.id, outcomes[task.id] ?? .failed("No result")) }
        }

        for task in userTasks {
            await onUpdate(task.id, nil)
            let result = await CommandRunner.run(task.command)
            await onUpdate(task.id, result.succeeded ? .succeeded : .failed(result.output))
        }
    }

    /// One shell script that runs every task and prints a marker line with each exit code.
    static func batchedCommand(for tasks: [MaintenanceTask]) -> String {
        tasks.map { task in
            "( \(task.command) ) >/dev/null 2>&1; echo \"__DAVINCI__\(task.id)__$?\""
        }
        .joined(separator: "; ")
    }

    static func parseBatchOutput(_ result: CommandResult, tasks: [MaintenanceTask]) -> [String: Outcome] {
        if result.wasCancelledByUser {
            return Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, Outcome.cancelled) })
        }
        var outcomes: [String: Outcome] = [:]
        for line in result.output.split(whereSeparator: \.isNewline) {
            let parts = line.components(separatedBy: "__")
            // "__DAVINCI__<id>__<code>" splits into ["", "DAVINCI", id, code].
            guard parts.count == 4, parts[1] == "DAVINCI" else { continue }
            outcomes[parts[2]] = parts[3] == "0" ? .succeeded : .failed("Exited with code \(parts[3])")
        }
        if outcomes.isEmpty && !result.succeeded {
            return Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, Outcome.failed(result.output)) })
        }
        return outcomes
    }
}
