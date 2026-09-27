import CleanerCore
import SwiftUI

struct Feature: Identifiable {
    let symbol: String
    let title: String
    let detail: String

    var id: String { title }
}

/// First screen of a module: hero icon, what it does, and the big round button.
struct IntroScreen<Accessory: View>: View {
    let module: Module
    let features: [Feature]
    var buttonTitle = "Scan"
    let action: () -> Void
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            HStack(alignment: .center, spacing: 56) {
                if !DebugLog.off("nohero") {
                    HeroIcon(symbol: module.symbol, palette: module.palette)
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text(module.title)
                        .font(.heroTitle)
                    Text(module.tagline)
                        .font(.title3)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(features) { feature in
                            FeatureRow(feature: feature)
                        }
                    }
                    .padding(.top, 10)
                }
                .frame(maxWidth: 440, alignment: .leading)
            }
            .padding(.horizontal, 40)
            Spacer(minLength: 24)
            if !DebugLog.off("nobutton") {
                ScanButton(title: buttonTitle, palette: module.palette, action: action)
            }
            accessory()
                .padding(.top, 18)
            Spacer(minLength: 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension IntroScreen where Accessory == EmptyView {
    init(module: Module, features: [Feature], buttonTitle: String = "Scan", action: @escaping () -> Void) {
        self.init(module: module, features: features, buttonTitle: buttonTitle, action: action) { EmptyView() }
    }
}

struct FeatureRow: View {
    let feature: Feature

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: feature.symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(Circle().fill(.white.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title).font(.cardTitle)
                Text(feature.detail)
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Shown while a module works: a ring, what it's looking at, and how much it found so far.
struct ScanningScreen: View {
    let module: Module
    var progress: Double?
    let headline: String
    var detail: String = ""
    var foundBytes: Int64?
    var onStop: (() -> Void)?

    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            ProgressRing(progress: progress, palette: module.palette) {
                VStack(spacing: 8) {
                    Image(systemName: module.symbol)
                        .font(.system(size: 42, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                    if let foundBytes {
                        Text(ByteFormatter.string(foundBytes))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.default, value: foundBytes)
                    }
                }
            }
            VStack(spacing: 8) {
                Text(headline)
                    .font(.sectionTitle)
                Text(detail)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 520)
            }
            Spacer()
            if let onStop {
                Button("Stop", action: onStop)
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Celebration screen after cleaning, with any problems listed underneath.
struct CompletionScreen: View {
    let module: Module
    let title: String
    let subtitle: String
    var failures: [RemovalReport.Failure] = []
    var onRetryAsAdministrator: (() -> Void)?
    let onDone: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 200, height: 200)
                    .scaleEffect(appeared ? 1 : 0.6)
                Circle()
                    .fill(.white)
                    .frame(width: 136, height: 136)
                    .shadow(color: module.palette.glow, radius: 34)
                Image(systemName: "checkmark")
                    .font(.system(size: 60, weight: .heavy))
                    .foregroundStyle(module.palette.top)
            }
            .scaleEffect(appeared ? 1 : 0.4)
            .opacity(appeared ? 1 : 0)
            Text(title)
                .font(.heroTitle)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            if !failures.isEmpty {
                FailureList(failures: failures, onRetryAsAdministrator: onRetryAsAdministrator)
                    .frame(maxWidth: 560)
            }
            Spacer()
            Button("Done", action: onDone)
                .buttonStyle(PillButtonStyle(kind: .primary, tint: module.palette.top))
                .keyboardShortcut(.defaultAction)
            Spacer(minLength: 24)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) { appeared = true }
        }
    }
}

struct FailureList: View {
    let failures: [RemovalReport.Failure]
    var onRetryAsAdministrator: (() -> Void)?
    @State private var expanded = false

    private var needsAdministrator: Bool { failures.contains { $0.needsAdministrator } }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warning)
                    Text("\(failures.count) item\(failures.count == 1 ? "" : "s") couldn't be removed")
                        .font(.cardTitle)
                    Spacer()
                    Button(expanded ? "Hide" : "Details") {
                        withAnimation { expanded.toggle() }
                    }
                    .buttonStyle(PillButtonStyle())
                }
                if expanded {
                    ForEach(failures.prefix(8)) { failure in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(failure.target.url.lastPathComponent).font(.callout.weight(.semibold))
                            Text(failure.reason)
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(2)
                        }
                    }
                    if failures.count > 8 {
                        Text("and \(failures.count - 8) more")
                            .font(.caption)
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }
                if needsAdministrator, let onRetryAsAdministrator {
                    Button {
                        onRetryAsAdministrator()
                    } label: {
                        Label("Remove with Administrator Rights", systemImage: "lock.open")
                    }
                    .buttonStyle(PillButtonStyle(kind: .primary))
                    Text("macOS will ask for your password. These items are deleted immediately, not moved to the Trash.")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
        }
    }
}

/// Header used on result screens: module badge, summary, and optional trailing controls.
struct ResultsHeader<Trailing: View>: View {
    let module: Module
    let title: String
    let subtitle: String
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .help("Start Over")
            }
            ModuleBadge(module: module, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.sectionTitle)
                    .contentTransition(.numericText())
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 16)
            trailing()
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 14)
    }
}

extension ResultsHeader where Trailing == EmptyView {
    init(module: Module, title: String, subtitle: String, onBack: (() -> Void)? = nil) {
        self.init(module: module, title: title, subtitle: subtitle, onBack: onBack) { EmptyView() }
    }
}

/// Bottom bar with a summary on the left and the module's round action button in the centre.
struct ActionBar<Leading: View>: View {
    let module: Module
    let buttonTitle: String
    var isEnabled = true
    let action: () -> Void
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            leading()
                .frame(maxWidth: .infinity, alignment: .leading)
            ScanButton(
                title: buttonTitle,
                palette: module.palette,
                diameter: 86,
                isEnabled: isEnabled,
                action: action
            )
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: 1)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.28)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        )
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.8))
            Text(title).font(.sectionTitle)
            Text(message)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

/// Tells the user when macOS is hiding folders from the app, and how to fix it.
struct FullDiskAccessBanner: View {
    let onOpenSettings: () -> Void
    let onRecheck: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 20))
                .foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Give DaVinci Cleaner Full Disk Access").font(.cardTitle)
                Text("Without it, macOS hides Mail, Safari and Trash folders, so scans find less.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Button("Check Again", action: onRecheck)
                .buttonStyle(PillButtonStyle())
            Button("Open Settings", action: onOpenSettings)
                .buttonStyle(PillButtonStyle(kind: .primary))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.warning.opacity(0.4)))
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}
