import CleanerCore
import SwiftUI

@MainActor
final class JunkViewModel: ObservableObject {
    enum Phase: Equatable { case idle, scanning, results, cleaning, done }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var results: [ScanCategory: [CleanupItem]] = [:]
    @Published private(set) var scannedCategories: Set<ScanCategory> = []
    @Published var selectedIDs: Set<String> = []
    @Published var focusedCategory: ScanCategory?
    @Published private(set) var report: RemovalReport?

    private let scanner = JunkScanner()
    private let remover = Remover()
    private var task: Task<Void, Never>?

    // MARK: - Derived values

    var progress: Double {
        Double(scannedCategories.count) / Double(ScanCategory.allCases.count)
    }

    var currentCategory: ScanCategory? {
        ScanCategory.allCases.first { !scannedCategories.contains($0) }
    }

    var allItems: [CleanupItem] {
        ScanCategory.allCases.flatMap { results[$0] ?? [] }
    }

    var totalFound: Int64 {
        allItems.reduce(0) { $0 + $1.size }
    }

    var selectedSize: Int64 {
        allItems.lazy.filter { self.selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    var categoriesWithResults: [ScanCategory] {
        ScanCategory.allCases.filter { !(results[$0] ?? []).isEmpty }
    }

    func items(in category: ScanCategory) -> [CleanupItem] {
        results[category] ?? []
    }

    func size(of category: ScanCategory) -> Int64 {
        items(in: category).reduce(0) { $0 + $1.size }
    }

    func selectedSize(in category: ScanCategory) -> Int64 {
        items(in: category).filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    func mark(for category: ScanCategory) -> CheckCircle.Mark {
        let items = items(in: category)
        return CheckCircle.Mark(selected: items.filter { selectedIDs.contains($0.id) }.count, total: items.count)
    }

    // MARK: - Selection

    func toggle(_ category: ScanCategory) {
        let ids = Set(items(in: category).map(\.id))
        if mark(for: category) == .on {
            selectedIDs.subtract(ids)
        } else {
            selectedIDs.formUnion(ids)
        }
    }

    func toggle(_ item: CleanupItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    // MARK: - Scanning

    func scan() {
        task?.cancel()
        task = Task { await runScan() }
    }

    /// Scans every category in parallel, publishing each one as it finishes.
    func runScan() async {
        results = [:]
        scannedCategories = []
        selectedIDs = []
        report = nil
        phase = .scanning

        let scanner = self.scanner
        await withTaskGroup(of: (ScanCategory, [CleanupItem]).self) { group in
            for category in ScanCategory.allCases {
                group.addTask { (category, scanner.scan(category)) }
            }
            for await (category, items) in group {
                await self.apply(items, for: category)
            }
        }
        guard !Task.isCancelled else { return }
        focusedCategory = categoriesWithResults.first
        withAnimation(.easeInOut(duration: 0.4)) { phase = .results }
    }

    private func apply(_ items: [CleanupItem], for category: ScanCategory) {
        results[category] = items
        scannedCategories.insert(category)
        selectedIDs.formUnion(items.filter(\.isSelectedByDefault).map(\.id))
    }

    func stop() {
        task?.cancel()
        withAnimation { phase = scannedCategories.isEmpty ? .idle : .results }
        focusedCategory = categoriesWithResults.first
    }

    func startOver() {
        task?.cancel()
        results = [:]
        scannedCategories = []
        selectedIDs = []
        report = nil
        withAnimation { phase = .idle }
    }

    // MARK: - Cleaning

    func clean() {
        task = Task {
            _ = await cleanSelected()
            withAnimation { phase = .done }
        }
    }

    /// Removes the selected items and returns what happened. Used by Smart Scan too.
    func cleanSelected() async -> RemovalReport {
        let targets = allItems.filter { selectedIDs.contains($0.id) }.map(\.removalTarget)
        guard !targets.isEmpty else { return RemovalReport() }
        phase = .cleaning
        let remover = self.remover
        let mode = Preferences.removalMode
        let report = await runInBackground { remover.remove(targets, mode: mode) }
        apply(report)
        phase = .results
        return report
    }

    private func apply(_ report: RemovalReport) {
        self.report = report
        let removed = Set(report.removed.map(\.path))
        for category in results.keys {
            results[category]?.removeAll { removed.contains($0.id) }
        }
        selectedIDs.subtract(removed)
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
            apply(updated)
        }
    }
}
