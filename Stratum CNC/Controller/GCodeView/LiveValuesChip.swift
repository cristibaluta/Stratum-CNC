//
//  LiveValuesChip.swift
//  Stratum CNC
//
//  One chip for the feed rate and Z at the current line, drawn like a tool chip and sitting at
//  the left of the tools bar. Its values change as the scrub position (or the running job) moves.
//

import SwiftUI

struct LiveValuesChip: View {

    /// `GCodeStore.currentLiveValues`.
    let values: GCodeLiveValues?

    private var feedText: String {
        if values?.isRapid == true {
            return "Rapid"
        }
        return values?.feed.map { "\($0) mm/min" } ?? "—"
    }

    private var zText: String {
        values?.z.map { "Z \($0)" } ?? "Z —"
    }

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 10) {
                Text("F")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)

                // Fixed width so the chip doesn't change size while the values scroll by.
                VStack(alignment: .leading, spacing: 0) {
                    Text(feedText)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundColor(values?.isRapid == true ? .secondary : .primary)
                    Text(zText)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundColor(.secondary)
                }
                .frame(width: 88, alignment: .leading)
            }
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 29)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.07))
            )

            // Same height as a tool chip, which has its current-tool marker here.
            Color.clear
                .frame(width: 12, height: 6)
        }
        .help("Feed rate and Z at the current line")
    }
}
