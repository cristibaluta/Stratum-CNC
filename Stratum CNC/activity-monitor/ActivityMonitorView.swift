//
//  ActivityMonitorView.swift
//  Stratum CNC
//
//  A little heartbeat for the toolbar: a pulse icon, CPU and memory as numbers, and a dot for
//  the thermal state. Click it for the last minute in graphs.
//
//  The toolbar part only redraws when a number visibly changes (see `ActivityMonitor.latest`);
//  the graphs live in the popover, which refreshes itself once a second while it is open. A
//  toolbar item that redraws every second keeps the CPU busy even when the app is idle.
//

import SwiftUI

struct ActivityMonitorView: View {

    @ObservedObject var monitor: ActivityMonitor
    @State private var isShowingDetails = false

    var body: some View {
        let latest = monitor.latest
        Button {
            isShowingDetails.toggle()
        } label: {
            compact(latest)
        }
        .buttonStyle(.plain)
        .help("CPU \(ActivityStyle.cpuText(latest.cpuPercent)) · Memory \(ActivityStyle.memoryText(latest.memoryMB)) · Thermal \(ProcessMetrics.thermalName(latest.thermal))")
        .popover(isPresented: $isShowingDetails, arrowEdge: .bottom) {
            // Polls the monitor's history while open; nothing is redrawn once it is closed
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                details(monitor.samples.last ?? monitor.latest)
            }
        }
        .task {
            await monitor.run()
        }
    }

    // MARK: Toolbar content

    private func compact(_ latest: ActivitySample) -> some View {
        return HStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg")
                .foregroundStyle(ActivityStyle.loadColor(latest.cpuPercent))
                .symbolEffect(.pulse, isActive: latest.cpuPercent >= ActivityStyle.busyCPU)

            Text(ActivityStyle.cpuText(latest.cpuPercent))
                .contentTransition(.numericText())
                .frame(minWidth: 34, alignment: .trailing)

            Text("·")
                .foregroundStyle(.tertiary)

            Text(ActivityStyle.memoryText(latest.memoryMB))
                .contentTransition(.numericText())
                .frame(minWidth: 52, alignment: .trailing)

            Circle()
                .fill(ActivityStyle.thermalColor(latest.thermal))
                .frame(width: 7, height: 7)
        }
        .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
        .animation(.snappy, value: ActivityStyle.cpuText(latest.cpuPercent))
        .animation(.snappy, value: ActivityStyle.memoryText(latest.memoryMB))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }

    // MARK: Popover

    private func details(_ latest: ActivitySample) -> some View {
        let cpuHistory = monitor.samples.map(\.cpuPercent)
        let memoryHistory = monitor.samples.map(\.memoryMB)

        return VStack(alignment: .leading, spacing: 14) {
            metric(title: "CPU",
                   value: ActivityStyle.cpuText(latest.cpuPercent),
                   color: ActivityStyle.loadColor(latest.cpuPercent),
                   values: cpuHistory,
                   range: 0...ActivityStyle.cpuScale(for: cpuHistory))

            metric(title: "Memory",
                   value: ActivityStyle.memoryText(latest.memoryMB),
                   color: .blue,
                   values: memoryHistory,
                   range: ActivityStyle.memoryRange(for: memoryHistory))

            HStack(spacing: 8) {
                Circle()
                    .fill(ActivityStyle.thermalColor(latest.thermal))
                    .frame(width: 9, height: 9)
                Text("Thermal")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer()
                Text(ProcessMetrics.thermalName(latest.thermal).capitalized)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Text("This app only · last \(ActivityMonitor.historyLength) seconds · 100% is one busy core of \(ProcessInfo.processInfo.activeProcessorCount)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 260)
    }

    private func metric(title: String,
                        value: String,
                        color: Color,
                        values: [Double],
                        range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Sparkline(values: values, window: ActivityMonitor.historyLength, range: range, color: color)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
        }
    }
}

// MARK: - Look

/// Thresholds, colors and number formats shared by the toolbar and the popover.
private enum ActivityStyle {

    /// CPU at which the icon starts to pulse and turns orange, and at which it turns red. Percent
    /// of one core, so 100 is a single busy thread, which is normal while a carve or a
    /// toolpath generation runs.
    static let busyCPU = 60.0
    static let hotCPU = 180.0

    static func loadColor(_ cpuPercent: Double) -> Color {
        if cpuPercent >= hotCPU {
            return .red
        }
        return cpuPercent >= busyCPU ? .orange : .green
    }

    static func thermalColor(_ state: ProcessInfo.ThermalState) -> Color {
        switch state {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .gray
        }
    }

    /// The top of a CPU graph: 100, or the next 100 above the highest value shown.
    static func cpuScale(for values: [Double]) -> Double {
        max(100, ((values.max() ?? 0) / 100).rounded(.up) * 100)
    }

    /// A memory graph follows the values, but never zooms into less than 20 MB so that a flat
    /// line doesn't look like a roller coaster.
    static func memoryRange(for values: [Double]) -> ClosedRange<Double> {
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let span = max(high - low, 20)
        return (low - span * 0.15)...(low + span * 1.15)
    }

    static func cpuText(_ percent: Double) -> String {
        String(format: "%.0f%%", percent)
    }

    static func memoryText(_ megabytes: Double) -> String {
        megabytes >= 1024
            ? String(format: "%.1f GB", megabytes / 1024)
            : String(format: "%.0f MB", max(megabytes, 0))
    }
}

/// A line graph with a soft fill, the newest value on the right. A fixed `window` keeps the
/// scale of time constant while the history is still filling up.
private struct Sparkline: View {

    let values: [Double]
    let window: Int
    let range: ClosedRange<Double>
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let points = points(in: geo.size)
            ZStack {
                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: geo.size.height))
                        for point in points {
                            path.addLine(to: point)
                        }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0.02)],
                                         startPoint: .top,
                                         endPoint: .bottom))

                    Path { path in
                        path.move(to: points[0])
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        let shown = Array(values.suffix(window))
        let step = window > 1 ? size.width / CGFloat(window - 1) : size.width
        let span = max(range.upperBound - range.lowerBound, .leastNonzeroMagnitude)
        let inset: CGFloat = 1.5

        return shown.enumerated().map { index, value in
            let fraction = min(max((value - range.lowerBound) / span, 0), 1)
            return CGPoint(x: size.width - CGFloat(shown.count - 1 - index) * step,
                           y: inset + (1 - CGFloat(fraction)) * (size.height - 2 * inset))
        }
    }
}
