import CleanerCore
import SwiftUI

// MARK: - Maintenance

struct MaintenanceView: View {
    @EnvironmentObject private var model: MaintenanceViewModel
    private let module = Module.maintenance
    private let columns = [GridItem(.adaptive(minimum: 300), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            ResultsHeader(
                module: module,
                title: "Maintenance",
                subtitle: "Pick the fixes to run. Recommended ones are already selected."
            ) {
                if model.hasRun && !model.isRunning {
                    Button("Reset", action: model.reset).buttonStyle(PillButtonStyle())
                }
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(model.tasks) { task in
                        MaintenanceCard(
                            task: task,
                            isSelected: model.selectedIDs.contains(task.id),
                            state: model.state(of: task),
                            tint: module.palette.glow
                        ) {
                            model.toggle(task)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
            ActionBar(
                module: module,
                buttonTitle: model.isRunning ? "Running" : "Run",
                isEnabled: !model.selectedIDs.isEmpty && !model.isRunning,
                action: model.run
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.selectedIDs.count) task\(model.selectedIDs.count == 1 ? "" : "s") selected")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    if model.needsPassword {
                        Label("macOS will ask for your password once", systemImage: "lock")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
    }
}

private struct MaintenanceCard: View {
    let task: MaintenanceTask
    let isSelected: Bool
    let state: MaintenanceViewModel.TaskState
    let tint: Color
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            GlassCard(padding: 16) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: task.symbolName)
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(tint.opacity(isSelected ? 0.45 : 0.18))
                        )
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(task.title).font(.cardTitle)
                            if task.requiresAdministrator {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.tertiaryText)
                                    .help("Needs your administrator password")
                            }
                        }
                        Text(task.summary)
                            .font(.callout)
                            .foregroundStyle(Theme.secondaryText)
                        Text("Use when: \(task.whenToUse)")
                            .font(.caption)
                            .foregroundStyle(Theme.tertiaryText)
                        statusView
                    }
                    Spacer(minLength: 0)
                    CheckCircle(mark: isSelected ? .on : .off, size: 20)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(isSelected ? 0.45 : 0), lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }

    @ViewBuilder
    private var statusView: some View {
        switch state {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Running…").font(.caption.weight(.semibold))
            }
        case .finished(.succeeded):
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.success)
        case .finished(.cancelled):
            Label("Cancelled", systemImage: "xmark.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        case .finished(.failed(let message)):
            Label(message.isEmpty ? "Failed" : message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.warning)
                .lineLimit(2)
        }
    }
}

// MARK: - Login items

struct LoginItemsView: View {
    @EnvironmentObject private var model: LoginItemsViewModel
    private let module = Module.loginItems

    var body: some View {
        if !model.hasLoaded {
            IntroScreen(
                module: module,
                features: [
                    Feature(symbol: "power", title: "Startup helpers", detail: "See every launch agent and daemon that starts in the background."),
                    Feature(symbol: "switch.2", title: "Switch off, not delete", detail: "Disable an item and turn it back on any time."),
                    Feature(symbol: "gearshape", title: "Login Items", detail: "Jump to System Settings for apps that open when you log in."),
                ],
                buttonTitle: "Show Items",
                action: model.load
            )
        } else {
            VStack(spacing: 0) {
                ResultsHeader(
                    module: module,
                    title: "\(model.enabledCount) items start automatically",
                    subtitle: "Turning off a helper can stop features of its app. You can always turn it back on."
                ) {
                    HStack {
                        SearchField(text: $model.searchText, prompt: "Filter")
                        Button("Login Items…", action: Finder.openLoginItemsSettings)
                            .buttonStyle(PillButtonStyle())
                            .help("Apps that open when you log in are managed in System Settings")
                    }
                }
                if model.isLoading {
                    ScanningScreen(module: module, progress: nil, headline: "Reading launch items…")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(LaunchItem.Scope.allCases, id: \.self) { scope in
                                let items = model.items(in: scope)
                                if !items.isEmpty {
                                    LaunchScopeSection(scope: scope, items: items, model: model)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                }
            }
            .alert(
                "Couldn't change the item",
                isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
            ) {
                Button("OK") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }
}

private struct LaunchScopeSection: View {
    let scope: LaunchItem.Scope
    let items: [LaunchItem]
    @ObservedObject var model: LoginItemsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(scope.title).font(.sectionTitle)
                Text(scope.explanation).font(.callout).foregroundStyle(Theme.secondaryText)
            }
            GlassCard(padding: 6) {
                VStack(spacing: 2) {
                    ForEach(items) { item in
                        HoverRow {
                            HStack(spacing: 12) {
                                Image(systemName: scope == .systemDaemon ? "gearshape.2.fill" : "bolt.horizontal.fill")
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(.white.opacity(0.12)))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.displayName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    Text(item.label)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(Theme.tertiaryText)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if scope == .systemDaemon {
                                    Image(systemName: "lock.fill")
                                        .font(.caption)
                                        .foregroundStyle(Theme.tertiaryText)
                                        .help("Needs your administrator password")
                                }
                                if model.busyIDs.contains(item.id) {
                                    ProgressView().controlSize(.small)
                                }
                                Toggle(
                                    "",
                                    isOn: Binding(
                                        get: { !item.isDisabled },
                                        set: { model.setEnabled($0, for: item) }
                                    )
                                )
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .disabled(model.busyIDs.contains(item.id))
                            }
                        }
                        .contextMenu {
                            Button("Reveal in Finder") { Finder.reveal(item.url) }
                            if item.scope == .userAgent {
                                Button("Remove", role: .destructive) { model.remove(item) }
                            }
                        }
                    }
                }
            }
        }
    }
}
