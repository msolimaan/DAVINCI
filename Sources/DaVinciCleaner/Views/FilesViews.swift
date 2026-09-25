import CleanerCore
import SwiftUI

// MARK: - Large & Old Files

struct LargeFilesView: View {
    @EnvironmentObject private var model: LargeFilesViewModel
    private let module = Module.largeFiles

    var body: some View {
        switch model.phase {
        case .idle:
            IntroScreen(
                module: module,
                features: [
                    Feature(symbol: "arrow.up.and.down.text.horizontal", title: "Biggest first", detail: "Files sorted by size, with filters for age and type."),
                    Feature(symbol: "clock.arrow.circlepath", title: "Forgotten files", detail: "Find things you haven't opened in months."),
                    Feature(symbol: "eye", title: "You decide", detail: "Nothing is pre-selected. Open or reveal anything before removing."),
                ],
                action: model.scan
            ) {
                ScopePicker(scope: $model.scope)
            }
        case .scanning:
            ScanningScreen(
                module: module,
                progress: nil,
                headline: "Looking for large files…",
                detail: "\(model.inspectedCount.formatted()) files checked in \(model.scope.title)",
                onStop: model.stop
            )
        case .results:
            LargeFilesResults(model: model, module: module)
        case .removing:
            ScanningScreen(module: module, progress: nil, headline: "Removing files…")
        case .done:
            CompletionScreen(
                module: module,
                title: "Files removed",
                subtitle: model.report?.summary ?? "",
                failures: model.report?.failures ?? [],
                onDone: model.backToResults
            )
        }
    }
}

/// Lets the user pick where a file scan looks.
struct ScopePicker: View {
    @Binding var scope: ScanScope

    var body: some View {
        HStack(spacing: 8) {
            Text("Look in").foregroundStyle(Theme.secondaryText)
            Menu {
                ForEach(ScanScope.presets, id: \.self) { preset in
                    Button(preset.title) { scope = preset }
                }
                Divider()
                Button("Choose Folder…") {
                    if let url = Finder.chooseFolder() { scope = .custom(url) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(scope.title)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(.white.opacity(0.14)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
    }
}

private struct LargeFilesResults: View {
    @ObservedObject var model: LargeFilesViewModel
    let module: Module

    var body: some View {
        let files = model.visibleFiles
        let largest = Double(files.map(\.size).max() ?? 1)
        VStack(spacing: 0) {
            ResultsHeader(
                module: module,
                title: "\(files.count) large file\(files.count == 1 ? "" : "s")",
                subtitle: "\(ByteFormatter.string(files.reduce(0) { $0 + $1.size })) in \(model.scope.title)",
                onBack: model.stop
            ) {
                Button("Rescan", action: model.scan).buttonStyle(PillButtonStyle())
            }
            filterBar
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
            Group {
                if files.isEmpty {
                    EmptyStateView(symbol: "checkmark.seal", title: "Nothing matches", message: "Try a smaller size or a different age filter.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(files) { file in
                                FileRow(
                                    file: file,
                                    isSelected: model.selectedIDs.contains(file.id),
                                    fraction: Double(file.size) / max(largest, 1),
                                    tint: module.palette.glow
                                ) {
                                    model.toggle(file)
                                }
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(Theme.cardFill))
            .padding(.horizontal, 20)
            ActionBar(
                module: module,
                buttonTitle: "Remove",
                isEnabled: !model.selectedIDs.isEmpty,
                action: model.removeSelected
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.selectedIDs.count) selected")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    SizeText(bytes: model.selectedSize, font: .system(size: 22, weight: .bold, design: .rounded))
                }
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            FilterMenu(title: "Size ≥", options: LargeFilesViewModel.sizeOptions, selection: $model.minimumSize)
            FilterMenu(
                title: "Last used",
                options: LargeFilesViewModel.AgeFilter.allCases.map { (value: $0, title: $0.title) },
                selection: $model.age
            )
            FilterMenu(
                title: "Sort",
                options: [
                    (LargeFilesViewModel.SortOrder.size, "Size"),
                    (.name, "Name"),
                    (.lastUsed, "Least Recently Used"),
                ],
                selection: $model.sortOrder
            )
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    KindChip(title: "All", symbol: "square.grid.2x2", isOn: model.kindFilter == nil) {
                        model.kindFilter = nil
                    }
                    ForEach(model.kindCounts, id: \.kind) { entry in
                        KindChip(
                            title: "\(entry.kind.title) \(entry.count)",
                            symbol: entry.kind.symbolName,
                            isOn: model.kindFilter == entry.kind
                        ) {
                            model.kindFilter = model.kindFilter == entry.kind ? nil : entry.kind
                        }
                    }
                }
            }
        }
    }
}

private struct KindChip: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(isOn ? Color.black.opacity(0.8) : .white)
                .background(Capsule().fill(isOn ? Color.white : Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

struct FileRow: View {
    let file: FileEntry
    let isSelected: Bool
    let fraction: Double
    let tint: Color
    var badge: String?
    let toggle: () -> Void

    var body: some View {
        HoverRow(isSelected: isSelected) {
            HStack(spacing: 10) {
                CheckButton(mark: isSelected ? .on : .off, action: toggle)
                FileIcon(url: file.url, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(file.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Theme.success.opacity(0.3)))
                        }
                    }
                    Text(Finder.abbreviated(file.url.deletingLastPathComponent()))
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 3) {
                    SizeText(bytes: file.size)
                    SizeBar(fraction: fraction, color: tint).frame(width: 90)
                }
                Text(file.lastActivity?.relativeDescription ?? "—")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 110, alignment: .trailing)
            }
        }
        .contextMenu {
            Button("Open") { Finder.open(file.url) }
            Button("Reveal in Finder") { Finder.reveal(file.url) }
        }
        .onTapGesture(count: 2) { Finder.reveal(file.url) }
    }
}

// MARK: - Duplicates

struct DuplicatesView: View {
    @EnvironmentObject private var model: DuplicatesViewModel
    private let module = Module.duplicates

    var body: some View {
        switch model.phase {
        case .idle:
            IntroScreen(
                module: module,
                features: [
                    Feature(symbol: "number", title: "Exact matches only", detail: "Files are compared by content (SHA-256), not by name."),
                    Feature(symbol: "wand.and.stars", title: "Smart selection", detail: "The oldest copy is kept; newer copies are selected."),
                    Feature(symbol: "lock", title: "One copy always stays", detail: "You can't select every copy of a file."),
                ],
                action: model.scan
            ) {
                ScopePicker(scope: $model.scope)
            }
        case .scanning:
            ScanningScreen(module: module, progress: nil, headline: "Comparing files…", detail: model.status, onStop: model.stop)
        case .results:
            DuplicateResults(model: model, module: module)
        case .removing:
            ScanningScreen(module: module, progress: nil, headline: "Removing copies…")
        case .done:
            CompletionScreen(
                module: module,
                title: "Duplicates removed",
                subtitle: model.report?.summary ?? "",
                failures: model.report?.failures ?? [],
                onDone: model.backToResults
            )
        }
    }
}

private struct DuplicateResults: View {
    @ObservedObject var model: DuplicatesViewModel
    let module: Module

    var body: some View {
        VStack(spacing: 0) {
            ResultsHeader(
                module: module,
                title: model.groups.isEmpty ? "No duplicates" : "\(ByteFormatter.string(model.wastedBytes)) in duplicates",
                subtitle: "\(model.groups.count) sets of identical files in \(model.scope.title)",
                onBack: model.stop
            ) {
                HStack {
                    Button("Smart Select", action: model.smartSelect).buttonStyle(PillButtonStyle())
                    Button("Deselect All") { model.selectedIDs = [] }.buttonStyle(PillButtonStyle())
                }
            }
            if model.groups.isEmpty {
                EmptyStateView(symbol: "checkmark.seal", title: "No duplicates found", message: "Every file here is unique.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.groups) { group in
                            GlassCard(padding: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(group.files.first?.name ?? "")
                                            .font(.cardTitle)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(group.files.count) copies · \(ByteFormatter.string(group.fileSize)) each")
                                            .font(.caption)
                                            .foregroundStyle(Theme.secondaryText)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.top, 6)
                                    ForEach(group.files) { file in
                                        FileRow(
                                            file: file,
                                            isSelected: model.selectedIDs.contains(file.id),
                                            fraction: 1,
                                            tint: module.palette.glow,
                                            badge: model.selectedIDs.contains(file.id) ? nil : "KEEP"
                                        ) {
                                            model.toggle(file, in: group)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }
            ActionBar(
                module: module,
                buttonTitle: "Remove",
                isEnabled: !model.selectedIDs.isEmpty,
                action: model.removeSelected
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.selectedIDs.count) copies selected")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    SizeText(bytes: model.selectedSize, font: .system(size: 22, weight: .bold, design: .rounded))
                }
            }
        }
    }
}
