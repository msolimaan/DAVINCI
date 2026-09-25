import CleanerCore
import SwiftUI

/// Smart Scan runs the most useful checks from several modules in one go, like CleanMyMac's Smart Care.
@MainActor
final class SmartScanViewModel: ObservableObject {
    enum Phase: Equatable { case idle, scanning, results, running, done }

    enum Stage: Int, CaseIterable, Identifiable {
        case cleanup, speed, clutter

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .cleanup: return "Cleanup"
            case .speed: return "Speed"
            case .clutter: return "Clutter"
            }
        }

        var symbol: String {
            switch self {
            case .cleanup: return "trash.circle.fill"
            case .speed: return "bolt.circle.fill"
            case .clutter: return "doc.circle.fill"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var completedStages: Set<Stage> = []
    @Published private(set) var activeStage: Stage?
    @Published private(set) var memory: MemorySnapshot?
    @Published private(set) var clutter: [FileEntry] = []
    @Published var includeSpeedTasks = true
    @Published private(set) var cleanupReport: RemovalReport?
    @Published private(set) var speedOutcomes: [String: MaintenanceRunner.Outcome] = [:]

    let junk: JunkViewModel
    private var task: Task<Void, Never>?

    /// Files at least this big in Downloads count as clutter.
    static let clutterThreshold: Int64 = 100 * 1_000_000

    init(junk: JunkViewModel) {
        self.junk = junk
    }

    var recommendedTasks: [MaintenanceTask] {
        MaintenanceTask.all.filter(\.isRecommended)
    }

    var clutterSize: Int64 {
        clutter.reduce(0) { $0 + $1.size }
    }

    var progress: Double {
        let stageShare = 1.0 / Double(Stage.allCases.count)
        var value = Double(completedStages.count) * stageShare
        if activeStage == .cleanup {
            value += junk.progress * stageShare
        }
        return min(1, value)
    }

    var speedSucceeded: Int {
        speedOutcomes.values.filter { $0 == .succeeded }.count
    }

    func scan() {
        task?.cancel()
        task = Task { await runScan() }
    }

    private func runScan() async {
        completedStages = []
        cleanupReport = nil
        speedOutcomes = [:]
        phase = .scanning

        activeStage = .cleanup
        await junk.runScan()
        guard !Task.isCancelled else { return }
        completedStages.insert(.cleanup)

        activeStage = .speed
        #if canImport(Darwin)
        memory = SystemStats.memory()
        #endif
        try? await Task.sleep(nanoseconds: 400_000_000)
        completedStages.insert(.speed)

        activeStage = .clutter
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let finder = LargeFileFinder()
        let options = LargeFileFinder.Options(minimumSize: Self.clutterThreshold)
        clutter = await runInBackground { finder.scan(root: downloads, options: options) }
        guard !Task.isCancelled else { return }
        completedStages.insert(.clutter)
        activeStage = nil

        withAnimation(.easeInOut(duration: 0.4)) { phase = .results }
    }

    func stop() {
        task?.cancel()
        junk.stop()
        withAnimation { phase = .idle }
    }

    func run() {
        task = Task {
            phase = .running
            cleanupReport = await junk.cleanSelected()
            if includeSpeedTasks {
                await MaintenanceRunner.run(recommendedTasks) { [weak self] id, outcome in
                    guard let outcome else { return }
                    await self?.record(outcome, for: id)
                }
            }
            withAnimation { phase = .done }
        }
    }

    private func record(_ outcome: MaintenanceRunner.Outcome, for id: String) {
        speedOutcomes[id] = outcome
    }

    func startOver() {
        task?.cancel()
        withAnimation { phase = .idle }
    }
}
