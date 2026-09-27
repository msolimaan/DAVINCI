import AppKit
import CleanerCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        switch DebugLog.variant {
        case "plain":
            Text("PLAIN VARIANT").font(.system(size: 60, weight: .bold)).foregroundColor(.red)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.yellow)
        case "split":
            NavigationSplitView {
                Text("SIDEBAR").font(.largeTitle)
            } detail: {
                Text("DETAIL").font(.system(size: 60, weight: .bold)).foregroundColor(.red)
            }
        case "splitlist":
            NavigationSplitView {
                SidebarView()
            } detail: {
                Text("DETAIL").font(.system(size: 60, weight: .bold)).foregroundColor(.red)
            }
        case "nobg":
            main(background: false)
        default:
            main(background: true)
        }
    }

    private func main(background: Bool) -> some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            ZStack(alignment: .top) {
                if background {
                    ModuleBackground(palette: state.selection.palette)
                        .id(state.selection)
                        .transition(.opacity)
                } else {
                    Color.purple
                }
                ModuleView(module: state.selection)
                    .id(state.selection)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                if !state.hasFullDiskAccess && !state.fullDiskAccessBannerDismissed {
                    FullDiskAccessBanner(
                        onOpenSettings: FullDiskAccess.openSettings,
                        onRecheck: state.recheckFullDiskAccess
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .foregroundStyle(.white)
            .animation(.easeInOut(duration: 0.35), value: state.selection)
        }
        .onAppear {
            DebugLog.write("RootView appeared")
            state.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.recheckFullDiskAccess()
        }
    }
}

/// Routes the sidebar selection to the module's screen.
struct ModuleView: View {
    let module: Module

    var body: some View {
        content.onAppear { DebugLog.write("ModuleView appeared: \(module.rawValue)") }
    }

    @ViewBuilder
    private var content: some View {
        switch module {
        case .smartScan: SmartScanView()
        case .systemJunk: SystemJunkView()
        case .uninstaller: UninstallerView()
        case .spaceLens: SpaceLensView()
        case .largeFiles: LargeFilesView()
        case .duplicates: DuplicatesView()
        case .maintenance: MaintenanceView()
        case .loginItems: LoginItemsView()
        case .monitor: MonitorView()
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var junk: JunkViewModel
    @EnvironmentObject private var monitor: MonitorViewModel

    var body: some View {
        List(selection: selection) {
            ForEach(Module.Group.allCases) { group in
                Section(group == .care ? "" : group.title) {
                    ForEach(group.modules) { module in
                        SidebarRow(module: module, badge: badge(for: module))
                            .tag(module)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .onAppear { DebugLog.write("Sidebar appeared") }
        .safeAreaInset(edge: .top) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Module.smartScan.palette.iconFill)
                    .frame(width: 28, height: 28)
                    .overlay(Image(systemName: "sparkles").font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 0) {
                    Text("DaVinci").font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("Cleaner").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 34)
            .padding(.bottom, 4)
        }
        .safeAreaInset(edge: .bottom) {
            DiskFooter(disk: monitor.disk)
        }
    }

    private var selection: Binding<Module?> {
        Binding(
            get: { state.selection },
            set: { if let module = $0 { state.show(module) } }
        )
    }

    private func badge(for module: Module) -> String? {
        switch module {
        case .systemJunk where junk.phase == .results && junk.totalFound > 0:
            return ByteFormatter.string(junk.totalFound)
        case .monitor:
            return monitor.memory.map { "\(Int(($0.usedFraction * 100).rounded()))%" }
        default:
            return nil
        }
    }
}

struct SidebarRow: View {
    let module: Module
    let badge: String?

    var body: some View {
        HStack(spacing: 10) {
            ModuleBadge(module: module, size: 24)
            Text(module.title)
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 4)
            if let badge {
                Text(badge)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.white.opacity(0.12)))
            }
        }
        .padding(.vertical, 3)
    }
}

struct DiskFooter: View {
    let disk: DiskSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "internaldrive.fill")
                Text("Macintosh HD").font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            if let disk {
                SizeBar(fraction: disk.usedFraction, color: disk.usedFraction > 0.9 ? Theme.danger : Color(hex: 0x7DD3FC))
                Text("\(ByteFormatter.string(disk.available)) available of \(ByteFormatter.string(disk.total))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.primary.opacity(0.06)))
        .padding(12)
    }
}
