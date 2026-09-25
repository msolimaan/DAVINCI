import CleanerCore
import SwiftUI

struct SystemJunkView: View {
    @EnvironmentObject private var model: JunkViewModel
    private let module = Module.systemJunk

    var body: some View {
        switch model.phase {
        case .idle:
            IntroScreen(
                module: module,
                features: [
                    Feature(symbol: "internaldrive", title: "Caches & logs", detail: "App caches and logs that are rebuilt automatically."),
                    Feature(symbol: "hammer", title: "Developer junk", detail: "Xcode DerivedData, simulators, Homebrew, npm, pip and more."),
                    Feature(symbol: "checkmark.shield", title: "Safe by design", detail: "System folders are off-limits and you review everything first."),
                ],
                action: model.scan
            )
        case .scanning:
            ScanningScreen(
                module: module,
                progress: model.progress,
                headline: "Scanning your Mac…",
                detail: model.currentCategory?.title ?? "",
                foundBytes: model.totalFound,
                onStop: model.stop
            )
        case .results:
            if model.categoriesWithResults.isEmpty {
                VStack {
                    ResultsHeader(module: module, title: "No junk found", subtitle: "Your Mac is already clean.", onBack: model.startOver)
                    EmptyStateView(symbol: "sparkles", title: "Squeaky clean", message: "There's nothing to remove right now. Check back in a few days.")
                }
            } else {
                JunkResultsView(model: model, module: module)
            }
        case .cleaning:
            ScanningScreen(module: module, progress: nil, headline: "Cleaning…", detail: "Removing the selected items")
        case .done:
            CompletionScreen(
                module: module,
                title: "Cleanup complete",
                subtitle: model.report?.summary ?? "",
                failures: model.report?.failures ?? [],
                onRetryAsAdministrator: model.retryAsAdministrator,
                onDone: model.startOver
            )
        }
    }
}

private struct JunkResultsView: View {
    @ObservedObject var model: JunkViewModel
    let module: Module

    var body: some View {
        VStack(spacing: 0) {
            ResultsHeader(
                module: module,
                title: "\(ByteFormatter.string(model.totalFound)) of junk found",
                subtitle: "Everything selected is safe to remove. Untick anything you'd like to keep.",
                onBack: model.startOver
            )
            HStack(alignment: .top, spacing: 16) {
                categoryList
                    .frame(width: 320)
                itemList
            }
            .padding(.horizontal, 20)
            ActionBar(
                module: module,
                buttonTitle: "Clean",
                isEnabled: model.selectedSize > 0,
                action: model.clean
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Selected")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    SizeText(bytes: model.selectedSize, font: .system(size: 22, weight: .bold, design: .rounded))
                    Text(Preferences.removalMode == .moveToTrash ? "Items go to the Trash" : "Items are deleted immediately")
                        .font(.caption2)
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
        }
    }

    private var categoryList: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(model.categoriesWithResults) { category in
                    HoverRow(isSelected: model.focusedCategory == category) {
                        HStack(spacing: 10) {
                            CheckButton(mark: model.mark(for: category)) { model.toggle(category) }
                            Image(systemName: category.symbolName)
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(.white.opacity(0.12)))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(category.title).font(.system(size: 13, weight: .semibold))
                                Text("\(model.items(in: category).count) items")
                                    .font(.caption)
                                    .foregroundStyle(Theme.tertiaryText)
                            }
                            Spacer()
                            SizeText(bytes: model.selectedSize(in: category))
                        }
                    }
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { model.focusedCategory = category }
                    }
                }
            }
            .padding(8)
        }
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(Theme.cardFill))
    }

    @ViewBuilder
    private var itemList: some View {
        if let category = model.focusedCategory {
            let items = model.items(in: category)
            let largest = Double(items.first?.size ?? 1)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.title).font(.sectionTitle)
                    Text(category.subtitle)
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(18)
                Divider().overlay(Color.white.opacity(0.1))
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(items) { item in
                            HoverRow {
                                HStack(spacing: 10) {
                                    CheckButton(mark: model.selectedIDs.contains(item.id) ? .on : .off) {
                                        model.toggle(item)
                                    }
                                    FileIcon(url: item.url, size: 26)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.name)
                                            .font(.system(size: 13, weight: .medium))
                                            .lineLimit(1)
                                        SizeBar(fraction: Double(item.size) / max(largest, 1), color: module.palette.glow)
                                            .frame(maxWidth: 220)
                                    }
                                    Spacer()
                                    SizeText(bytes: item.size)
                                }
                            }
                            .contextMenu {
                                Button("Reveal in Finder") { Finder.reveal(item.url) }
                            }
                            .help(Finder.abbreviated(item.url))
                        }
                    }
                    .padding(8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(Theme.cardFill))
        } else {
            EmptyStateView(symbol: "sidebar.left", title: "Pick a category", message: "Choose a category on the left to see its items.")
        }
    }
}
