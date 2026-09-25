import CleanerCore
import SwiftUI

struct UninstallerView: View {
    @EnvironmentObject private var model: UninstallerViewModel
    private let module = Module.uninstaller

    var body: some View {
        switch model.phase {
        case .idle:
            IntroScreen(
                module: module,
                features: [
                    Feature(symbol: "square.stack.3d.up", title: "Complete removal", detail: "Deletes the app plus its caches, preferences, containers and helpers."),
                    Feature(symbol: "magnifyingglass", title: "Find leftovers", detail: "Spots files from apps you already deleted by dragging to the Trash."),
                    Feature(symbol: "lock.shield", title: "Apple apps protected", detail: "Built-in macOS apps are never listed."),
                ],
                buttonTitle: "View Apps",
                action: model.load
            )
        case .loading:
            ScanningScreen(module: module, progress: nil, headline: "Finding your apps…")
        case .ready:
            AppsBrowser(model: model, module: module)
        case .removing:
            ScanningScreen(module: module, progress: nil, headline: "Uninstalling…", detail: "Removing apps and their files")
        case .done:
            CompletionScreen(
                module: module,
                title: "Uninstall complete",
                subtitle: model.report?.summary ?? "",
                failures: model.report?.failures ?? [],
                onRetryAsAdministrator: model.retryAsAdministrator,
                onDone: model.finish
            )
        }
    }
}

private struct AppsBrowser: View {
    @ObservedObject var model: UninstallerViewModel
    let module: Module

    var body: some View {
        VStack(spacing: 0) {
            ResultsHeader(
                module: module,
                title: model.tab == .applications ? "\(model.apps.count) Applications" : "Leftovers",
                subtitle: model.tab == .applications
                    ? "Tick the apps to remove. Click an app to see every file it owns."
                    : "Files left behind by apps that are no longer installed."
            ) {
                GlassSegmentedPicker(
                    options: [(UninstallerViewModel.Tab.applications, "Applications"), (.leftovers, "Leftovers")],
                    selection: $model.tab
                )
            }
            switch model.tab {
            case .applications: applications
            case .leftovers: leftovers
            }
        }
        .alert("Quit running apps?", isPresented: $model.isConfirmingQuit) {
            Button("Quit & Uninstall", role: .destructive) { model.quitAndUninstall() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(model.appsToQuit.joined(separator: ", ")) must quit before being removed. Unsaved changes may be lost.")
        }
    }

    // MARK: Applications

    private var applications: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                appList.frame(width: 380)
                appDetail
            }
            .padding(.horizontal, 20)
            ActionBar(
                module: module,
                buttonTitle: "Uninstall",
                isEnabled: !model.checkedAppIDs.isEmpty,
                action: model.requestUninstall
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.checkedAppIDs.count) app\(model.checkedAppIDs.count == 1 ? "" : "s") selected")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    SizeText(bytes: model.checkedSize, font: .system(size: 22, weight: .bold, design: .rounded))
                }
            }
        }
    }

    private var appList: some View {
        VStack(spacing: 8) {
            HStack {
                SearchField(text: $model.searchText, prompt: "Search apps")
                Spacer()
                FilterMenu(
                    title: "Sort:",
                    options: [
                        (UninstallerViewModel.SortOrder.size, "Size"),
                        (.name, "Name"),
                        (.lastUsed, "Least Used"),
                    ],
                    selection: $model.sortOrder
                )
            }
            .padding([.horizontal, .top], 10)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.visibleApps) { app in
                        HoverRow(isSelected: model.focusedAppID == app.id) {
                            HStack(spacing: 10) {
                                CheckButton(mark: model.checkedAppIDs.contains(app.id) ? .on : .off) {
                                    model.toggleChecked(app)
                                }
                                FileIcon(url: app.url, size: 32)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(app.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    Text(app.lastUsed.map { "Used \($0.relativeDescription)" } ?? (app.version.map { "Version \($0)" } ?? ""))
                                        .font(.caption)
                                        .foregroundStyle(Theme.tertiaryText)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if app.size > 0 {
                                    SizeText(bytes: app.size)
                                } else {
                                    ProgressView().controlSize(.small)
                                }
                            }
                        }
                        .onTapGesture { model.focus(app) }
                        .contextMenu {
                            Button("Reveal in Finder") { Finder.reveal(app.url) }
                        }
                    }
                }
                .padding(8)
            }
        }
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(Theme.cardFill))
    }

    @ViewBuilder
    private var appDetail: some View {
        if let app = model.focusedApp {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 16) {
                    FileIcon(url: app.url, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name).font(.sectionTitle)
                        Text(app.bundleIdentifier)
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.tertiaryText)
                        SizeText(bytes: model.removalSize(for: app), font: .system(size: 15, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    Button(model.checkedAppIDs.contains(app.id) ? "Selected" : "Select") {
                        model.toggleChecked(app)
                    }
                    .buttonStyle(PillButtonStyle(kind: model.checkedAppIDs.contains(app.id) ? .primary : .secondary, tint: module.palette.top))
                }
                .padding(18)
                Divider().overlay(Color.white.opacity(0.1))
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        fileRow(
                            url: app.url,
                            title: "\(app.name).app",
                            location: "Application",
                            size: app.size,
                            mark: .on,
                            action: nil
                        )
                        if let files = model.files(for: app) {
                            ForEach(files) { file in
                                fileRow(
                                    url: file.url,
                                    title: file.url.lastPathComponent,
                                    location: file.location + (file.isSystemWide ? " · needs password" : ""),
                                    size: file.size,
                                    mark: model.excludedFileIDs.contains(file.id) ? .off : .on
                                ) {
                                    model.toggleFile(file)
                                }
                            }
                            if files.isEmpty {
                                Text("No other files found for this app.")
                                    .font(.callout)
                                    .foregroundStyle(Theme.tertiaryText)
                                    .padding(12)
                            }
                        } else {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Looking for related files…").foregroundStyle(Theme.secondaryText)
                            }
                            .padding(12)
                        }
                    }
                    .padding(8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(Theme.cardFill))
        } else {
            EmptyStateView(symbol: "app.dashed", title: "No app selected", message: "Pick an app to see its files.")
        }
    }

    private func fileRow(
        url: URL,
        title: String,
        location: String,
        size: Int64,
        mark: CheckCircle.Mark,
        action: (() -> Void)?
    ) -> some View {
        HoverRow {
            HStack(spacing: 10) {
                if let action {
                    CheckButton(mark: mark, action: action)
                } else {
                    CheckCircle(mark: mark).padding(4).opacity(0.5)
                }
                FileIcon(url: url, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(location).font(.caption).foregroundStyle(Theme.tertiaryText)
                }
                Spacer()
                SizeText(bytes: size)
            }
        }
        .contextMenu {
            Button("Reveal in Finder") { Finder.reveal(url) }
        }
        .help(Finder.abbreviated(url))
    }

    // MARK: Leftovers

    private var leftovers: some View {
        VStack(spacing: 0) {
            Group {
                if model.isLoadingOrphans {
                    ScanningScreen(module: module, progress: nil, headline: "Looking for leftovers…")
                } else if model.orphans.isEmpty {
                    VStack(spacing: 18) {
                        EmptyStateView(
                            symbol: "sparkle.magnifyingglass",
                            title: "Find leftovers",
                            message: "Apps deleted by dragging them to the Trash leave settings and caches behind. Scan to find them."
                        )
                        Button("Scan for Leftovers", action: model.loadOrphans)
                            .buttonStyle(PillButtonStyle(kind: .primary, tint: module.palette.top))
                            .padding(.bottom, 40)
                    }
                } else {
                    orphanList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !model.orphans.isEmpty {
                ActionBar(
                    module: module,
                    buttonTitle: "Remove",
                    isEnabled: !model.selectedOrphanIDs.isEmpty,
                    action: model.removeSelectedOrphans
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(model.selectedOrphanIDs.count) selected")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                        SizeText(bytes: model.selectedOrphanSize, font: .system(size: 22, weight: .bold, design: .rounded))
                    }
                }
            }
        }
    }

    private var orphanList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                Text("Nothing is selected for you: review each item. Apps installed outside /Applications can show up here.")
                    .font(.callout)
            }
            .foregroundStyle(Theme.secondaryText)
            .padding(16)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.orphans) { file in
                        fileRow(
                            url: file.url,
                            title: file.url.lastPathComponent,
                            location: file.location,
                            size: file.size,
                            mark: model.selectedOrphanIDs.contains(file.id) ? .on : .off
                        ) {
                            model.toggleOrphan(file)
                        }
                    }
                }
                .padding(8)
            }
        }
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(Theme.cardFill))
        .padding(.horizontal, 20)
    }
}
