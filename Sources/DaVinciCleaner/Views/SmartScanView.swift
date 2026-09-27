import CleanerCore
import SwiftUI

struct SmartScanView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var model: SmartScanViewModel
    @EnvironmentObject private var junk: JunkViewModel

    private let module = Module.smartScan

    var body: some View {
        switch model.phase {
        case .idle:
            IntroScreen(
                module: module,
                features: [
                    Feature(symbol: "trash", title: "Cleanup", detail: "Caches, logs, developer junk, browser data and the Trash."),
                    Feature(symbol: "bolt", title: "Speed", detail: "Checks memory pressure and runs quick maintenance."),
                    Feature(symbol: "doc.on.doc", title: "Clutter", detail: "Spots big files lying around in Downloads."),
                ],
                action: model.scan
            ) {
                Text(greeting)
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
            }
        case .scanning:
            ScanningScreen(
                module: module,
                progress: model.progress,
                headline: headline,
                detail: detail,
                foundBytes: junk.totalFound,
                onStop: model.stop
            )
            .overlay(alignment: .bottom) { stageStrip.padding(.bottom, 110) }
        case .results:
            results
        case .running:
            ScanningScreen(module: module, progress: nil, headline: "Working on it…", detail: "Cleaning junk and running maintenance tasks")
        case .done:
            CompletionScreen(
                module: module,
                title: "Your Mac is in great shape",
                subtitle: doneSubtitle,
                failures: model.cleanupReport?.failures ?? [],
                onRetryAsAdministrator: junk.retryAsAdministrator,
                onDone: model.startOver
            )
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let time = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
        return "\(time). A scan takes about a minute and changes nothing until you say so."
    }

    private var headline: String {
        switch model.activeStage {
        case .cleanup: return "Looking for junk…"
        case .speed: return "Checking performance…"
        case .clutter: return "Looking for clutter…"
        case nil: return "Finishing up…"
        }
    }

    private var detail: String {
        if model.activeStage == .cleanup, let category = junk.currentCategory {
            return category.title
        }
        return ""
    }

    private var stageStrip: some View {
        HStack(spacing: 26) {
            ForEach(SmartScanViewModel.Stage.allCases) { stage in
                let done = model.completedStages.contains(stage)
                let active = model.activeStage == stage
                HStack(spacing: 6) {
                    Image(systemName: done ? "checkmark.circle.fill" : stage.symbol)
                        .foregroundStyle(done ? Theme.success : .white.opacity(active ? 1 : 0.5))
                    Text(stage.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .opacity(done || active ? 1 : 0.5)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Capsule().fill(.white.opacity(0.1)))
    }

    private var doneSubtitle: String {
        var parts: [String] = []
        if let report = model.cleanupReport, !report.removed.isEmpty {
            parts.append(report.summary)
        }
        if model.includeSpeedTasks && !model.speedOutcomes.isEmpty {
            parts.append("\(model.speedSucceeded) of \(model.recommendedTasks.count) speed tasks completed.")
        }
        return parts.isEmpty ? "Nothing needed cleaning." : parts.joined(separator: " ")
    }

    // MARK: - Results

    private var results: some View {
        VStack(spacing: 0) {
            ResultsHeader(
                module: module,
                title: "Scan complete",
                subtitle: "Here's what we found. Review any card, or press Run to take care of it all.",
                onBack: model.startOver
            )
            ScrollView {
                HStack(alignment: .top, spacing: 18) {
                    SmartCard(
                        symbol: "trash.circle.fill",
                        title: "Cleanup",
                        value: ByteFormatter.string(junk.selectedSize),
                        caption: "of junk selected across \(junk.categoriesWithResults.count) categories",
                        tint: Module.systemJunk.palette.glow,
                        actionTitle: "Review Details"
                    ) {
                        state.show(.systemJunk)
                    }
                    SmartCard(
                        symbol: "bolt.circle.fill",
                        title: "Speed",
                        value: "\(model.recommendedTasks.count) tasks",
                        caption: speedCaption,
                        tint: Module.maintenance.palette.glow,
                        actionTitle: "Review Tasks"
                    ) {
                        state.show(.maintenance)
                    } footer: {
                        Toggle("Run speed tasks", isOn: $model.includeSpeedTasks)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .font(.caption)
                    }
                    SmartCard(
                        symbol: "doc.circle.fill",
                        title: "Clutter",
                        value: model.clutter.isEmpty ? "All clear" : ByteFormatter.string(model.clutterSize),
                        caption: model.clutter.isEmpty
                            ? "No big files in Downloads"
                            : "in \(model.clutter.count) large file\(model.clutter.count == 1 ? "" : "s") in Downloads",
                        tint: Module.largeFiles.palette.glow,
                        actionTitle: "Review Files"
                    ) {
                        state.reviewClutter()
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 10)
            }
            ActionBar(module: module, buttonTitle: "Run", action: model.run) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ready to clean")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    SizeText(bytes: junk.selectedSize, font: .system(size: 22, weight: .bold, design: .rounded))
                }
            }
        }
    }

    private var speedCaption: String {
        guard let memory = model.memory else { return "recommended maintenance" }
        return "recommended · memory pressure is \(memory.pressure.title.lowercased())"
    }
}

/// One of the three summary cards on the Smart Scan results screen.
private struct SmartCard<Footer: View>: View {
    let symbol: String
    let title: String
    let value: String
    let caption: String
    let tint: Color
    let actionTitle: String
    let action: () -> Void
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        GlassCard(padding: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 40))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .shadow(color: tint.opacity(0.6), radius: 12)
                Text(title)
                    .font(.cardTitle)
                    .foregroundStyle(Theme.secondaryText)
                Text(value)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(caption)
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
                footer()
                Spacer(minLength: 0)
                Button(actionTitle, action: action)
                    .buttonStyle(PillButtonStyle())
            }
            .frame(minHeight: 280, alignment: .topLeading)
        }
    }
}

extension SmartCard where Footer == EmptyView {
    init(
        symbol: String,
        title: String,
        value: String,
        caption: String,
        tint: Color,
        actionTitle: String,
        action: @escaping () -> Void
    ) {
        self.init(
            symbol: symbol,
            title: title,
            value: value,
            caption: caption,
            tint: tint,
            actionTitle: actionTitle,
            action: action
        ) { EmptyView() }
    }
}
