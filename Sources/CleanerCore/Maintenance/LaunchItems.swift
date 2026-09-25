import Foundation

/// A launch agent or daemon: a background helper that macOS starts at login or boot.
public struct LaunchItem: Identifiable, Hashable, Sendable {
    public enum Scope: String, CaseIterable, Sendable {
        case userAgent, systemAgent, systemDaemon

        public var title: String {
            switch self {
            case .userAgent: return "Your Launch Agents"
            case .systemAgent: return "Launch Agents for All Users"
            case .systemDaemon: return "System Daemons"
            }
        }

        public var explanation: String {
            switch self {
            case .userAgent: return "Helpers that start when you log in."
            case .systemAgent: return "Helpers that start for every user who logs in."
            case .systemDaemon: return "Background services that start with your Mac, before anyone logs in."
            }
        }
    }

    public var id: String { url.path }
    public let url: URL
    public let label: String
    public let program: String?
    public let scope: Scope
    public let runsAtLoad: Bool
    public var isDisabled: Bool

    public var displayName: String {
        if let program {
            let name = URL(fileURLWithPath: program).lastPathComponent
            if !name.isEmpty { return name }
        }
        return label
    }
}

/// Reads launch items and enables or disables them with `launchctl`.
public struct LaunchItemStore: Sendable {
    public let home: URL
    public let systemLibrary: URL

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemLibrary: URL = URL(fileURLWithPath: "/Library")
    ) {
        self.home = home
        self.systemLibrary = systemLibrary
    }

    var userID: String { String(getuid()) }

    public func load() async -> [LaunchItem] {
        async let userDisabled = CommandRunner.run("/bin/launchctl print-disabled gui/\(userID)")
        async let systemDisabled = CommandRunner.run("/bin/launchctl print-disabled system")
        let disabledForUser = Self.parseDisabled(await userDisabled.output)
        let disabledForSystem = Self.parseDisabled(await systemDisabled.output)

        let folders: [(URL, LaunchItem.Scope)] = [
            (home.appendingPathComponent("Library/LaunchAgents"), .userAgent),
            (systemLibrary.appendingPathComponent("LaunchAgents"), .systemAgent),
            (systemLibrary.appendingPathComponent("LaunchDaemons"), .systemDaemon),
        ]
        var items: [LaunchItem] = []
        for (folder, scope) in folders {
            let disabled = scope == .systemDaemon ? disabledForSystem : disabledForUser
            items += Self.readItems(in: folder, scope: scope, disabledLabels: disabled)
        }
        return items.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    static func readItems(in folder: URL, scope: LaunchItem.Scope, disabledLabels: Set<String>) -> [LaunchItem] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.compactMap { url in
            guard url.pathExtension == "plist",
                  let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                return nil
            }
            let label = (plist["Label"] as? String) ?? url.deletingPathExtension().lastPathComponent
            let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
            let disabledInPlist = (plist["Disabled"] as? Bool) ?? false
            return LaunchItem(
                url: url,
                label: label,
                program: program,
                scope: scope,
                runsAtLoad: (plist["RunAtLoad"] as? Bool) ?? false,
                isDisabled: disabledInPlist || disabledLabels.contains(label)
            )
        }
    }

    /// Enables or disables an item. Agents are handled in your login session; daemons need an administrator.
    public func setEnabled(_ enabled: Bool, for item: LaunchItem) async -> CommandResult {
        let domain = item.scope == .systemDaemon ? "system" : "gui/\(userID)"
        let service = CommandRunner.shellQuote("\(domain)/\(item.label)")
        let plist = CommandRunner.shellQuote(item.url.path)
        let command: String
        if enabled {
            command = "/bin/launchctl enable \(service); /bin/launchctl bootstrap \(domain) \(plist) 2>/dev/null; true"
        } else {
            command = "/bin/launchctl disable \(service); /bin/launchctl bootout \(domain) \(plist) 2>/dev/null; true"
        }
        return await CommandRunner.run(command, asAdministrator: item.scope == .systemDaemon)
    }

    /// Parses `launchctl print-disabled` output, e.g. `"com.vendor.agent" => disabled` (or `=> true` on older macOS).
    public static func parseDisabled(_ output: String) -> Set<String> {
        var labels = Set<String>()
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let state = parts[1].trimmingCharacters(in: .whitespaces)
            guard state == "disabled" || state == "true" else { continue }
            let label = parts[0]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !label.isEmpty { labels.insert(label) }
        }
        return labels
    }
}
