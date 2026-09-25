import CleanerCore
import SwiftUI

/// Where a file scan looks.
enum ScanScope: Hashable {
    case home, downloads, desktop, documents, custom(URL)

    static let presets: [ScanScope] = [.home, .downloads, .desktop, .documents]

    var url: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .home: return home
        case .downloads: return home.appendingPathComponent("Downloads")
        case .desktop: return home.appendingPathComponent("Desktop")
        case .documents: return home.appendingPathComponent("Documents")
        case .custom(let url): return url
        }
    }

    var title: String {
        switch self {
        case .home: return "Home Folder"
        case .downloads: return "Downloads"
        case .desktop: return "Desktop"
        case .documents: return "Documents"
        case .custom(let url): return url.lastPathComponent
        }
    }
}

// MARK: - Space Lens

@MainActor
final class SpaceLensViewModel: ObservableObject {
    enum Phase: Equatable { case idle, browsing }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var root: URL = FileManager.default.homeDirectoryForCurrentUser
    @Published private(set) var path: [URL] = []
    @Published private(set) var nodes: [SpaceNode] = []
    @Published private(set) var isLoading = false
    @Published var selectedIDs: Set<String> = []
    @Published var hoveredID: String?
    @Published private(set) var report: RemovalReport?

    private var cache: [String: [SpaceNode]] = [:]
    private var task: Task<Void, Never>?
    private let analyzer = SpaceAnalyzer()
    private let remover = Remover()

    var current: URL { path.last ?? root }
    var totalSize: Int64 { nodes.reduce(0) { $0 + $1.size } }
    var selectedNodes: [SpaceNode] { nodes.filter { selectedIDs.contains($0.id) } }
    var selectedSize: Int64 { selectedNodes.reduce(0) { $0 + $1.size } }
    var hoveredNode: SpaceNode? { nodes.first { $0.id == hoveredID } }

    func start(at url: URL) {
        root = url
        path = [url]
        cache = [:]
        selectedIDs = []
        withAnimation { phase = .browsing }
        load(url)
    }

    func open(_ node: SpaceNode) {
        guard node.isFolder else { return }
        path.append(node.url)
        selectedIDs = []
        load(node.url)
    }

    func goTo(depth: Int) {
        guard depth < path.count else { return }
        path = Array(path.prefix(depth + 1))
        selectedIDs = []
        load(current)
    }

    func goUp() {
        guard path.count > 1 else { return }
        goTo(depth: path.count - 2)
    }

    func close() {
        task?.cancel()
        withAnimation { phase = .idle }
    }

    private func load(_ url: URL) {
        task?.cancel()
        if let cached = cache[url.path] {
            withAnimation(.easeInOut(duration: 0.3)) { nodes = cached }
            isLoading = false
            return
        }
        isLoading = true
        let analyzer = self.analyzer
        task = Task {
            let children = await analyzer.children(of: url)
            guard !Task.isCancelled, current == url else { return }
            cache[url.path] = children
            withAnimation(.easeInOut(duration: 0.35)) { nodes = children }
            isLoading = false
        }
    }

    func toggle(_ node: SpaceNode) {
        if selectedIDs.contains(node.id) {
            selectedIDs.remove(node.id)
        } else {
            selectedIDs.insert(node.id)
        }
    }

    func removeSelected() {
        let root = self.root
        let targets = selectedNodes.map { RemovalTarget(url: $0.url, allowedRoot: root, size: $0.size) }
        guard !targets.isEmpty else { return }
        let remover = self.remover
        let mode = Preferences.removalMode
        Task {
            let report = await runInBackground { remover.remove(targets, mode: mode) }
            self.report = report
            // Sizes of this folder and every parent changed.
            for url in path { cache[url.path] = nil }
            selectedIDs = []
            load(current)
        }
    }

    func dismissReport() {
        report = nil
    }
}

// MARK: - Large & Old Files

@MainActor
final class LargeFilesViewModel: ObservableObject {
    enum Phase: Equatable { case idle, scanning, results, removing, done }

    enum AgeFilter: Int, Hashable, CaseIterable {
        case any = 0, month = 30, halfYear = 182, year = 365

        var title: String {
            switch self {
            case .any: return "Any Time"
            case .month: return "1+ Month Ago"
            case .halfYear: return "6+ Months Ago"
            case .year: return "1+ Year Ago"
            }
        }
    }

    enum SortOrder: Hashable { case size, name, lastUsed }

    static let sizeOptions: [(value: Int64, title: String)] = [
        (50_000_000, "50 MB"), (100_000_000, "100 MB"), (500_000_000, "500 MB"), (1_000_000_000, "1 GB"),
    ]

    @Published private(set) var phase: Phase = .idle
    @Published var scope: ScanScope = .home
    @Published var minimumSize: Int64 = 100_000_000
    @Published var age: AgeFilter = .any
    @Published var kindFilter: FileKind?
    @Published var sortOrder: SortOrder = .size
    @Published private(set) var files: [FileEntry] = []
    @Published var selectedIDs: Set<String> = []
    @Published private(set) var inspectedCount = 0
    @Published private(set) var report: RemovalReport?

    private var task: Task<Void, Never>?
    private let remover = Remover()

    /// Files matching the size, age and kind filters (size and age are applied live after a scan).
    var visibleFiles: [FileEntry] {
        let cutoff = age == .any ? nil : Date().addingTimeInterval(-Double(age.rawValue) * 86_400)
        let filtered = files.filter { file in
            guard file.size >= minimumSize else { return false }
            if let kindFilter, file.kind != kindFilter { return false }
            if let cutoff, let activity = file.lastActivity, activity > cutoff { return false }
            return true
        }
        switch sortOrder {
        case .size: return filtered
        case .name: return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .lastUsed: return filtered.sorted { ($0.lastActivity ?? .distantPast) < ($1.lastActivity ?? .distantPast) }
        }
    }

    var kindCounts: [(kind: FileKind, count: Int, size: Int64)] {
        let visible = files.filter { $0.size >= minimumSize }
        return FileKind.allCases.compactMap { kind in
            let matches = visible.filter { $0.kind == kind }
            guard !matches.isEmpty else { return nil }
            return (kind, matches.count, matches.reduce(0) { $0 + $1.size })
        }
    }

    var selectedSize: Int64 {
        files.filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    func scan() {
        task?.cancel()
        files = []
        selectedIDs = []
        inspectedCount = 0
        report = nil
        phase = .scanning
        let root = scope.url
        // Scan at the smallest size offered so the size filter can change without rescanning.
        let options = LargeFileFinder.Options(minimumSize: Self.sizeOptions[0].value)
        let finder = LargeFileFinder()
        task = Task {
            let found = await runInBackground {
                finder.scan(root: root, options: options) { [weak self] count in
                    Task { @MainActor in self?.inspectedCount = count }
                }
            }
            guard !Task.isCancelled else { return }
            files = found
            withAnimation { phase = .results }
        }
    }

    func stop() {
        task?.cancel()
        withAnimation { phase = .idle }
    }

    func toggle(_ file: FileEntry) {
        if selectedIDs.contains(file.id) {
            selectedIDs.remove(file.id)
        } else {
            selectedIDs.insert(file.id)
        }
    }

    func removeSelected() {
        let targets = files.filter { selectedIDs.contains($0.id) }.map(\.removalTarget)
        guard !targets.isEmpty else { return }
        let remover = self.remover
        let mode = Preferences.removalMode
        phase = .removing
        Task {
            let report = await runInBackground { remover.remove(targets, mode: mode) }
            self.report = report
            let removed = Set(report.removed.map(\.path))
            files.removeAll { removed.contains($0.id) }
            selectedIDs.subtract(removed)
            withAnimation { phase = .done }
        }
    }

    func backToResults() {
        report = nil
        withAnimation { phase = .results }
    }
}

// MARK: - Duplicates

@MainActor
final class DuplicatesViewModel: ObservableObject {
    enum Phase: Equatable { case idle, scanning, results, removing, done }

    @Published private(set) var phase: Phase = .idle
    @Published var scope: ScanScope = .home
    @Published private(set) var groups: [DuplicateGroup] = []
    @Published var selectedIDs: Set<String> = []
    @Published private(set) var status = ""
    @Published private(set) var report: RemovalReport?

    private var task: Task<Void, Never>?
    private let remover = Remover()

    var wastedBytes: Int64 { groups.reduce(0) { $0 + $1.wastedBytes } }

    var selectedSize: Int64 {
        groups.flatMap(\.files).filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    func scan() {
        task?.cancel()
        groups = []
        selectedIDs = []
        report = nil
        status = "Collecting files…"
        phase = .scanning
        let root = scope.url
        let finder = DuplicateFinder()
        task = Task {
            let found = await runInBackground {
                finder.scan(root: root) { [weak self] message in
                    Task { @MainActor in self?.status = message }
                }
            }
            guard !Task.isCancelled else { return }
            groups = found
            smartSelect()
            withAnimation { phase = .results }
        }
    }

    func stop() {
        task?.cancel()
        withAnimation { phase = .idle }
    }

    /// Selects every copy except the oldest one in each group.
    func smartSelect() {
        selectedIDs = Set(groups.flatMap { $0.files.dropFirst().map(\.id) })
    }

    func toggle(_ file: FileEntry, in group: DuplicateGroup) {
        if selectedIDs.contains(file.id) {
            selectedIDs.remove(file.id)
        } else {
            // Never let the user select every copy: at least one must survive.
            let others = group.files.filter { $0.id != file.id }
            guard others.contains(where: { !selectedIDs.contains($0.id) }) else { return }
            selectedIDs.insert(file.id)
        }
    }

    func removeSelected() {
        let targets = groups.flatMap(\.files).filter { selectedIDs.contains($0.id) }.map(\.removalTarget)
        guard !targets.isEmpty else { return }
        let remover = self.remover
        let mode = Preferences.removalMode
        phase = .removing
        Task {
            let report = await runInBackground { remover.remove(targets, mode: mode) }
            self.report = report
            let removed = Set(report.removed.map(\.path))
            groups = groups.compactMap { group in
                let remaining = group.files.filter { !removed.contains($0.id) }
                return remaining.count > 1 ? DuplicateGroup(id: group.id, files: remaining) : nil
            }
            selectedIDs.subtract(removed)
            withAnimation { phase = .done }
        }
    }

    func backToResults() {
        report = nil
        withAnimation { phase = groups.isEmpty ? .idle : .results }
    }
}
