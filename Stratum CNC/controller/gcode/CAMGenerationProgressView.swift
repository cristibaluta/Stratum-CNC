//
//  CAMGenerationProgressView.swift
//  Stratum CNC
//
//  The popover shown by "Use from CAM" / "Refresh from CAM" while it generates the toolpaths
//  that weren't ready: every toolpath of the project, with its state, and an overall bar.
//

import SwiftUI

struct CAMGenerationProgressView: View {

    @ObservedObject var store: GCodeStore

    /// More rows than this scroll instead of growing the popover.
    private static let maxVisibleRows = 8

    private var finishedCount: Int {
        store.camProgress.filter { $0.state.isFinished }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(store.isBuildingCAMGCode ? "Building G-code…" : "Generating toolpaths…")
                    .font(.headline)
                Spacer()
                Text("\(finishedCount) of \(store.camProgress.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(finishedCount), total: Double(max(store.camProgress.count, 1)))

            Divider()

            if store.camProgress.count > Self.maxVisibleRows {
                ScrollView {
                    rows
                }
                .frame(height: 260)
            } else {
                rows
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(store.camProgress) { item in
                CAMProgressRow(item: item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CAMProgressRow: View {

    let item: GCodeStore.CAMProgressItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            icon
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(item.state == .waiting ? .secondary : .primary)

                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch item.state {
            case .waiting:
                Image(systemName: "circle.dotted")
                    .foregroundStyle(.secondary)
            case .generating:
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            case .ready:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .skipped:
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.orange)
        }
    }

    private var detail: String? {
        switch item.state {
            case .waiting: nil
            case .generating: "Generating…"
            case .ready: nil
            case .failed(let message), .skipped(let message): message
        }
    }
}
