import AppKit
import CleanerCore
import SwiftUI

/// The popover behind the menu bar icon: live stats and one-click fixes, in the spirit of Stats and CleanMyMac Menu.
struct MenuBarView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var monitor: MonitorViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ModuleBadge(module: .smartScan, size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text("DaVinci Cleaner").font(.system(size: 14, weight: .bold, design: .rounded))
                    Text("Up \(monitor.uptime)").font(.caption).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                MiniGauge(title: "CPU", fraction: monitor.cpu.usage, color: Color(hex: 0x7DD3FC))
                MiniGauge(
                    title: "Memory",
                    fraction: monitor.memory?.usedFraction ?? 0,
                    color: monitor.memory?.pressure == .normal ? Theme.success : Theme.warning
                )
                MiniGauge(title: "Disk", fraction: monitor.disk?.usedFraction ?? 0, color: Color(hex: 0xC4B5FD))
            }

            if let disk = monitor.disk {
                Text("\(ByteFormatter.string(disk.available)) free on Macintosh HD")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Top memory users").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                ForEach(monitor.processes.prefix(4)) { process in
                    HStack {
                        Text(process.name).font(.system(size: 12)).lineLimit(1)
                        Spacer()
                        Text(ByteFormatter.string(Int64(process.memoryBytes)))
                            .font(.system(size: 12, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }

            if let toast = monitor.toast {
                Text(toast).font(.caption.weight(.semibold)).foregroundStyle(Theme.success)
            }

            HStack(spacing: 8) {
                Button(monitor.isFreeingMemory ? "Freeing…" : "Free Up RAM", action: monitor.freeMemory)
                    .buttonStyle(PillButtonStyle())
                    .disabled(monitor.isFreeingMemory)
                Button(monitor.isEmptyingTrash ? "Emptying…" : "Empty Trash", action: monitor.emptyTrash)
                    .buttonStyle(PillButtonStyle())
                    .disabled(monitor.isEmptyingTrash)
            }

            Divider().overlay(Color.white.opacity(0.15))

            HStack {
                Button("Open DaVinci Cleaner") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(PillButtonStyle(kind: .primary, tint: Module.smartScan.palette.top))
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(PillButtonStyle())
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(width: 320)
        .background(ModuleBackground(palette: Module.smartScan.palette))
    }
}

private struct MiniGauge: View {
    let title: String
    let fraction: Double
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            GaugeRing(fraction: fraction, color: color, diameter: 58, lineWidth: 7)
                .overlay(
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                )
            Text(title).font(.caption).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.08)))
    }
}
