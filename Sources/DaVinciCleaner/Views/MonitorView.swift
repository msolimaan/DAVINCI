import Charts
import CleanerCore
import SwiftUI

struct MonitorView: View {
    @EnvironmentObject private var model: MonitorViewModel
    private let module = Module.monitor

    var body: some View {
        VStack(spacing: 0) {
            ResultsHeader(
                module: module,
                title: "System Monitor",
                subtitle: "Up \(model.uptime) · updates every 2 seconds"
            ) {
                HStack {
                    Button {
                        model.freeMemory()
                    } label: {
                        Label(model.isFreeingMemory ? "Freeing…" : "Free Up RAM", systemImage: "memorychip")
                    }
                    .buttonStyle(PillButtonStyle())
                    .disabled(model.isFreeingMemory)
                    Button {
                        model.emptyTrash()
                    } label: {
                        Label(model.isEmptyingTrash ? "Emptying…" : "Empty Trash", systemImage: "trash")
                    }
                    .buttonStyle(PillButtonStyle())
                    .disabled(model.isEmptyingTrash)
                }
            }
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        StatCard(
                            title: "CPU",
                            fraction: model.cpu.usage,
                            value: percent(model.cpu.usage),
                            caption: "User \(percent(model.cpu.user)) · System \(percent(model.cpu.system))",
                            color: Color(hex: 0x7DD3FC)
                        )
                        StatCard(
                            title: "Memory",
                            fraction: model.memory?.usedFraction ?? 0,
                            value: model.memory.map { ByteFormatter.string(Int64($0.used)) } ?? "–",
                            caption: memoryCaption,
                            color: memoryColor
                        )
                        StatCard(
                            title: "Disk",
                            fraction: model.disk?.usedFraction ?? 0,
                            value: model.disk.map { ByteFormatter.string($0.available) } ?? "–",
                            caption: model.disk.map { "free of \(ByteFormatter.string($0.total))" } ?? "",
                            color: (model.disk?.usedFraction ?? 0) > 0.9 ? Theme.danger : Color(hex: 0xC4B5FD)
                        )
                    }
                    HStack(alignment: .top, spacing: 16) {
                        historyChart
                        processList.frame(width: 340)
                    }
                    if let memory = model.memory {
                        memoryBreakdown(memory)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(.black.opacity(0.6)))
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        withAnimation { model.toast = nil }
                    }
            }
        }
        .animation(.spring(), value: model.toast)
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private var memoryCaption: String {
        guard let memory = model.memory else { return "" }
        return "of \(ByteFormatter.string(Int64(memory.total))) · pressure \(memory.pressure.title.lowercased())"
    }

    private var memoryColor: Color {
        switch model.memory?.pressure {
        case .critical: return Theme.danger
        case .warning: return Theme.warning
        default: return Theme.success
        }
    }

    private var historyChart: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Last 3 minutes").font(.cardTitle)
                    Spacer()
                    LegendDot(color: Color(hex: 0x7DD3FC), title: "CPU")
                    LegendDot(color: memoryColor, title: "Memory")
                }
                Chart(model.history) { sample in
                    AreaMark(x: .value("Time", sample.id), y: .value("CPU", sample.cpu * 100))
                        .foregroundStyle(
                            LinearGradient(colors: [Color(hex: 0x7DD3FC).opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                        )
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Time", sample.id), y: .value("Memory", sample.memory * 100))
                        .foregroundStyle(memoryColor)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { value in
                        AxisGridLine().foregroundStyle(.white.opacity(0.12))
                        AxisValueLabel {
                            if let number = value.as(Int.self) {
                                Text("\(number)%").foregroundStyle(Theme.tertiaryText)
                            }
                        }
                    }
                }
                .frame(height: 220)
            }
        }
    }

    private var processList: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Using the most memory").font(.cardTitle)
                let largest = Double(model.processes.first?.memoryBytes ?? 1)
                ForEach(model.processes) { process in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(process.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Spacer()
                            Text(ByteFormatter.string(Int64(process.memoryBytes)))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                        SizeBar(fraction: Double(process.memoryBytes) / max(largest, 1), color: Color(hex: 0xA5B4FC))
                    }
                }
                if model.processes.isEmpty {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    private func memoryBreakdown(_ memory: MemorySnapshot) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Memory breakdown").font(.cardTitle)
                GeometryReader { proxy in
                    let total = Double(max(memory.total, 1))
                    HStack(spacing: 2) {
                        segment(memory.app, total: total, width: proxy.size.width, color: Color(hex: 0x60A5FA))
                        segment(memory.wired, total: total, width: proxy.size.width, color: Color(hex: 0xF472B6))
                        segment(memory.compressed, total: total, width: proxy.size.width, color: Color(hex: 0xFACC15))
                        segment(memory.cached, total: total, width: proxy.size.width, color: Color(hex: 0x34D399).opacity(0.6))
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 14)
                .background(Capsule().fill(.white.opacity(0.08)))
                .clipShape(Capsule())
                HStack(spacing: 18) {
                    LegendDot(color: Color(hex: 0x60A5FA), title: "App \(ByteFormatter.string(Int64(memory.app)))")
                    LegendDot(color: Color(hex: 0xF472B6), title: "Wired \(ByteFormatter.string(Int64(memory.wired)))")
                    LegendDot(color: Color(hex: 0xFACC15), title: "Compressed \(ByteFormatter.string(Int64(memory.compressed)))")
                    LegendDot(color: Color(hex: 0x34D399), title: "Cached files \(ByteFormatter.string(Int64(memory.cached)))")
                }
            }
        }
    }

    private func segment(_ bytes: UInt64, total: Double, width: CGFloat, color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: max(0, width * CGFloat(Double(bytes) / total) - 2))
    }
}

private struct StatCard: View {
    let title: String
    let fraction: Double
    let value: String
    let caption: String
    let color: Color

    var body: some View {
        GlassCard(padding: 20) {
            HStack(spacing: 18) {
                GaugeRing(fraction: fraction, color: color, diameter: 92, lineWidth: 10)
                    .overlay(
                        Text("\(Int((fraction * 100).rounded()))%")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.cardTitle).foregroundStyle(Theme.secondaryText)
                    Text(value)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct LegendDot: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.caption).foregroundStyle(Theme.secondaryText)
        }
    }
}
