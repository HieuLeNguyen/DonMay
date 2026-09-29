import Charts
import SwiftUI

struct PerformanceView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hiệu năng").font(.largeTitle.weight(.bold))
                Text("Cập nhật mỗi 2 giây.").foregroundStyle(.secondary)
            }
            Grid(horizontalSpacing: 12) {
                GridRow {
                    let mem = state.memory
                    let pressure = Double(mem.used) / Double(max(mem.total, 1))
                    MetricCard(title: "RAM", value: "\(Format.bytes(mem.used)) / \(Format.bytes(mem.total))",
                               detail: "Nén \(Format.bytes(mem.compressed)) · swap \(Format.bytes(mem.swapUsed))",
                               series: state.memoryHistory, color: pressure > 0.85 ? Palette.warn : Palette.accent)
                    MetricCard(title: "CPU", value: Format.percent(state.cpuHistory.last ?? 0),
                               detail: "\(ProcessInfo.processInfo.activeProcessorCount) nhân",
                               series: state.cpuHistory, color: Palette.accent)
                    MetricCard(title: "GPU", value: Format.percent(state.gpuHistory.last ?? 0),
                               detail: "Theo IOAccelerator", series: state.gpuHistory, color: Palette.accent)
                    MetricCard(title: "Ổ đĩa", value: Format.bytes(state.diskFree),
                               detail: "còn trống trên \(Format.bytes(state.diskTotal))", series: [], color: Palette.alert)
                }
            }
            VStack(spacing: 0) {
                HStack {
                    Text("Tiến trình dùng nhiều CPU nhất").fontWeight(.semibold)
                    Spacer()
                    Text("CPU").frame(width: 80, alignment: .trailing)
                    Text("RAM").frame(width: 100, alignment: .trailing)
                }
                .font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Color.primary.opacity(0.04))
                ForEach(state.processes) { process in
                    Divider()
                    HStack {
                        Text(process.name)
                        Spacer()
                        Text(Format.percent(process.cpu)).monospacedDigit().frame(width: 80, alignment: .trailing)
                        Text(Format.bytes(process.memory)).monospacedDigit().frame(width: 100, alignment: .trailing)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let series: [Double]
    let color: Color

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                Text(value).font(.title2.weight(.semibold)).monospacedDigit()
                Chart(Array(series.enumerated()), id: \.offset) { point in
                    AreaMark(x: .value("t", point.offset), y: .value("v", point.element))
                        .foregroundStyle(color.opacity(0.15))
                    LineMark(x: .value("t", point.offset), y: .value("v", point.element))
                        .foregroundStyle(color)
                }
                .chartYScale(domain: 0...1)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 36)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
