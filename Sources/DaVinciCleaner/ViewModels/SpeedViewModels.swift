import CleanerCore
import SwiftUI

// MARK: - Maintenance

@MainActor
final class MaintenanceViewModel: ObservableObject {
    enum TaskState: Equatable {
        case idle, running
        case finished(MaintenanceRunner.Outcome)
    }

    let tasks = MaintenanceTask.all
    @Published var selectedIDs: Set<String> = Set(MaintenanceTask.all.filter(\.isRecommended).map(\.id))
    @Published private(set) var states: [String: TaskState] = [:]
    @Published private(set) var isRunning = false
    @Published private(set) var hasRun = false

    var selectedTasks: [MaintenanceTask] { tasks.filter { selectedIDs.contains($0.id) } }
    var needsPassword: Bool { selectedTasks.contains(where: \.requiresAdministrator) }

    func state(of task: MaintenanceTask) -> TaskState { states[task.id] ?? .idle }

    func toggle(_ task: MaintenanceTask) {
        guard !isRunning else { return }
        if selectedIDs.contains(task.id) {
            selectedIDs.remove(task.id)
        } else {
            selectedIDs.insert(task.id)
        }
    }

    func run() {
        let tasks = selectedTasks
        guard !tasks.isEmpty, !isRunning else { return }
        isRunning = true
        states = [:]
        Task {
            await MaintenanceRunner.run(tasks) { [weak self] id, outcome in
                await self?.update(id, outcome: outcome)
            }
            isRunning = false
            hasRun = true
        }
    }

    private func update(_ id: String, outcome: MaintenanceRunner.Outcome?) {
        withAnimation { states[id] = outcome.map { .finished($0) } ?? .running }
    }

    func reset() {
        states = [:]
        hasRun = false
    }
}

// MARK: - Login items

@MainActor
final class LoginItemsViewModel: ObservableObject {
    @Published private(set) var items: [LaunchItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var busyIDs: Set<String> = []
    @Published var searchText = ""
    @Published var errorMessage: String?
    @Published private(set) var hasLoaded = false

    private let store = LaunchItemStore()
    private let remover = Remover()

    func items(in scope: LaunchItem.Scope) -> [LaunchItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return items.filter { item in
            item.scope == scope
                && (query.isEmpty
                    || item.label.localizedCaseInsensitiveContains(query)
                    || item.displayName.localizedCaseInsensitiveContains(query))
        }
    }

    var enabledCount: Int { items.filter { !$0.isDisabled }.count }

    func load() {
        isLoading = true
        hasLoaded = true
        let store = self.store
        Task {
            let loaded = await store.load()
            withAnimation { items = loaded }
            isLoading = false
        }
    }

    func setEnabled(_ enabled: Bool, for item: LaunchItem) {
        busyIDs.insert(item.id)
        let store = self.store
        Task {
            let result = await store.setEnabled(enabled, for: item)
            busyIDs.remove(item.id)
            if result.succeeded, let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].isDisabled = !enabled
            } else if !result.succeeded, !result.wasCancelledByUser {
                errorMessage = result.output.isEmpty ? "launchctl couldn't change \(item.label)." : result.output
            }
        }
    }

    /// Removes one of your own launch agents: stops it, then moves its plist away.
    func remove(_ item: LaunchItem) {
        guard item.scope == .userAgent else { return }
        busyIDs.insert(item.id)
        let store = self.store
        let remover = self.remover
        let mode = Preferences.removalMode
        Task {
            _ = await store.setEnabled(false, for: item)
            let target = RemovalTarget(url: item.url, allowedRoot: item.url.deletingLastPathComponent(), size: 0)
            let report = await runInBackground { remover.remove([target], mode: mode) }
            busyIDs.remove(item.id)
            if let failure = report.failures.first {
                errorMessage = failure.reason
            } else {
                withAnimation { items.removeAll { $0.id == item.id } }
            }
        }
    }
}

// MARK: - Monitor

@MainActor
final class MonitorViewModel: ObservableObject {
    struct Sample: Identifiable {
        let id: Int
        let cpu: Double
        let memory: Double
    }

    @Published private(set) var cpu: CPUSnapshot = .zero
    @Published private(set) var memory: MemorySnapshot?
    @Published private(set) var disk: DiskSnapshot?
    @Published private(set) var history: [Sample] = []
    @Published private(set) var processes: [ProcessUsage] = []
    @Published private(set) var isFreeingMemory = false
    @Published private(set) var isEmptyingTrash = false
    @Published var toast: String?

    static let historyLength = 90
    private let sampler = CPUSampler()
    private var timer: Timer?
    private var tick = 0

    var uptime: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: SystemStats.uptime) ?? "–"
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        cpu = sampler.sample()
        memory = SystemStats.memory()
        disk = SystemStats.disk()
        tick += 1
        history.append(Sample(id: tick, cpu: cpu.usage, memory: memory?.usedFraction ?? 0))
        if history.count > Self.historyLength {
            history.removeFirst(history.count - Self.historyLength)
        }
        if tick % 3 == 1 {
            Task { processes = await SystemStats.topProcesses(limit: 8) }
        }
    }

    func freeMemory() {
        guard !isFreeingMemory else { return }
        isFreeingMemory = true
        let before = memory?.used ?? 0
        Task {
            let result = await CommandRunner.run("/usr/sbin/purge", asAdministrator: true)
            refresh()
            isFreeingMemory = false
            if result.succeeded {
                let after = memory?.used ?? before
                let freed = before > after ? Int64(before - after) : 0
                toast = freed > 0 ? "Freed \(ByteFormatter.string(freed)) of memory" : "Memory caches cleared"
            } else if !result.wasCancelledByUser {
                toast = "Couldn't free memory: \(result.output)"
            }
        }
    }

    func emptyTrash() {
        guard !isEmptyingTrash else { return }
        isEmptyingTrash = true
        Task {
            let scanner = JunkScanner()
            let remover = Remover()
            let report = await runInBackground {
                remover.remove(scanner.scan(.trash).map(\.removalTarget), mode: .deletePermanently)
            }
            isEmptyingTrash = false
            toast = report.removed.isEmpty
                ? "The Trash is already empty"
                : "Emptied the Trash and freed \(ByteFormatter.string(report.freedBytes))"
            disk = SystemStats.disk()
        }
    }
}
