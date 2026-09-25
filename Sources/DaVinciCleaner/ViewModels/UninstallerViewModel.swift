import AppKit
import CleanerCore
import SwiftUI

@MainActor
final class UninstallerViewModel: ObservableObject {
    enum Tab: Hashable { case applications, leftovers }
    enum Phase: Equatable { case idle, loading, ready, removing, done }
    enum SortOrder: Hashable { case name, size, lastUsed }

    @Published var tab: Tab = .applications
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var sizesLoaded = false
    @Published var searchText = ""
    @Published var sortOrder: SortOrder = .size
    @Published var checkedAppIDs: Set<String> = []
    @Published var focusedAppID: String?
    @Published private(set) var leftovers: [String: [LeftoverFile]] = [:]
    @Published var excludedFileIDs: Set<String> = []
    @Published private(set) var orphans: [LeftoverFile] = []
    @Published var selectedOrphanIDs: Set<String> = []
    @Published private(set) var isLoadingOrphans = false
    @Published private(set) var report: RemovalReport?
    @Published var appsToQuit: [String] = []
    @Published var isConfirmingQuit = false

    private let finder = LeftoverFinder()
    private let remover = Remover()

    // MARK: - Derived values

    var visibleApps: [InstalledApp] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let filtered = query.isEmpty ? apps : apps.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
        switch sortOrder {
        case .name:
            return filtered
        case .size:
            return filtered.sorted { $0.size > $1.size }
        case .lastUsed:
            return filtered.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        }
    }

    var focusedApp: InstalledApp? {
        apps.first { $0.id == focusedAppID }
    }

    var checkedApps: [InstalledApp] {
        apps.filter { checkedAppIDs.contains($0.id) }
    }

    func files(for app: InstalledApp) -> [LeftoverFile]? {
        leftovers[app.id]
    }

    /// App bundle plus the leftovers still ticked.
    func removalSize(for app: InstalledApp) -> Int64 {
        let files = (leftovers[app.id] ?? []).filter { !excludedFileIDs.contains($0.id) }
        return app.size + files.reduce(0) { $0 + $1.size }
    }

    var checkedSize: Int64 {
        checkedApps.reduce(0) { $0 + removalSize(for: $1) }
    }

    var selectedOrphanSize: Int64 {
        orphans.filter { selectedOrphanIDs.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    // MARK: - Loading

    func load() {
        phase = .loading
        Task {
            let inventory = AppInventory()
            let list = await runInBackground { inventory.loadApps() }
            apps = list
            focusedAppID = focusedAppID ?? list.first?.id
            if let first = focusedApp { loadLeftovers(for: first) }
            withAnimation { phase = .ready }
            await measureSizes(of: list)
        }
    }

    private func measureSizes(of list: [InstalledApp]) async {
        sizesLoaded = false
        await withTaskGroup(of: (String, Int64).self) { group in
            for app in list {
                group.addTask { (app.id, DirectorySizer.size(of: app.url)) }
            }
            for await (id, size) in group {
                await self.setSize(size, for: id)
            }
        }
        sizesLoaded = true
    }

    private func setSize(_ size: Int64, for id: String) {
        if let index = apps.firstIndex(where: { $0.id == id }) {
            apps[index].size = size
        }
    }

    func focus(_ app: InstalledApp) {
        focusedAppID = app.id
        loadLeftovers(for: app)
    }

    func loadLeftovers(for app: InstalledApp) {
        guard leftovers[app.id] == nil else { return }
        let finder = self.finder
        Task {
            let files = await runInBackground { finder.leftovers(for: app) }
            leftovers[app.id] = files
        }
    }

    // MARK: - Selection

    func toggleChecked(_ app: InstalledApp) {
        if checkedAppIDs.contains(app.id) {
            checkedAppIDs.remove(app.id)
        } else {
            checkedAppIDs.insert(app.id)
            loadLeftovers(for: app)
        }
    }

    func toggleFile(_ file: LeftoverFile) {
        if excludedFileIDs.contains(file.id) {
            excludedFileIDs.remove(file.id)
        } else {
            excludedFileIDs.insert(file.id)
        }
    }

    func toggleOrphan(_ file: LeftoverFile) {
        if selectedOrphanIDs.contains(file.id) {
            selectedOrphanIDs.remove(file.id)
        } else {
            selectedOrphanIDs.insert(file.id)
        }
    }

    // MARK: - Uninstalling

    /// Asks to quit running apps first, then uninstalls.
    func requestUninstall() {
        let running = checkedApps.filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleIdentifier).isEmpty }
        if running.isEmpty {
            uninstall()
        } else {
            appsToQuit = running.map(\.name)
            isConfirmingQuit = true
        }
    }

    func quitAndUninstall() {
        Task {
            for app in checkedApps {
                for running in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier) {
                    running.terminate()
                }
            }
            // Give apps a moment to save and quit.
            for _ in 0..<20 {
                let stillRunning = checkedApps.contains {
                    !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleIdentifier).isEmpty
                }
                if !stillRunning { break }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            uninstall()
        }
    }

    private func uninstall() {
        let selected = checkedApps
        guard !selected.isEmpty else { return }
        phase = .removing
        let finder = self.finder
        let remover = self.remover
        let mode = Preferences.removalMode
        let excluded = excludedFileIDs
        let known = leftovers

        Task {
            let report = await runInBackground { () -> RemovalReport in
                var targets: [RemovalTarget] = []
                for app in selected {
                    let files = known[app.id] ?? finder.leftovers(for: app)
                    // Leftovers first: the app bundle goes last so a failure leaves nothing half-removed.
                    targets += files.filter { !excluded.contains($0.id) }.map(\.removalTarget)
                    targets.append(
                        RemovalTarget(url: app.url, allowedRoot: app.url.deletingLastPathComponent(), size: app.size)
                    )
                }
                return remover.remove(targets, mode: mode)
            }
            self.report = report
            let removedPaths = Set(report.removed.map(\.path))
            apps.removeAll { removedPaths.contains($0.id) }
            checkedAppIDs.subtract(removedPaths)
            if let focusedAppID, removedPaths.contains(focusedAppID) {
                self.focusedAppID = apps.first?.id
            }
            withAnimation { phase = .done }
        }
    }

    func retryAsAdministrator() {
        guard let report else { return }
        let targets = report.failures.filter(\.needsAdministrator).map(\.target)
        guard let command = remover.privilegedRemovalCommand(for: targets) else { return }
        Task {
            let result = await CommandRunner.run(command, asAdministrator: true)
            guard result.succeeded else { return }
            var updated = report
            updated.failures.removeAll { $0.needsAdministrator }
            updated.removed += targets.map(\.url)
            updated.freedBytes += targets.reduce(0) { $0 + $1.size }
            self.report = updated
            let removedPaths = Set(targets.map(\.url.path))
            apps.removeAll { removedPaths.contains($0.id) }
        }
    }

    func finish() {
        report = nil
        withAnimation { phase = .ready }
    }

    // MARK: - Orphaned leftovers

    func loadOrphans() {
        isLoadingOrphans = true
        let finder = self.finder
        Task {
            let everyApp = await runInBackground { AppInventory().loadApps(includeAppleApps: true) }
            let identifiers = Set(everyApp.map(\.bundleIdentifier))
            let found = await runInBackground {
                finder.orphans(installedBundleIdentifiers: identifiers) { identifier in
                    NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) != nil
                }
            }
            orphans = found
            selectedOrphanIDs = []
            isLoadingOrphans = false
        }
    }

    func removeSelectedOrphans() {
        let targets = orphans.filter { selectedOrphanIDs.contains($0.id) }.map(\.removalTarget)
        guard !targets.isEmpty else { return }
        let remover = self.remover
        let mode = Preferences.removalMode
        phase = .removing
        Task {
            let report = await runInBackground { remover.remove(targets, mode: mode) }
            self.report = report
            let removed = Set(report.removed.map(\.path))
            orphans.removeAll { removed.contains($0.id) }
            selectedOrphanIDs.subtract(removed)
            withAnimation { phase = .done }
        }
    }
}
