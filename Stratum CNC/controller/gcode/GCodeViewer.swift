//
//  GCodeViewer.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import SwiftUI
import AppKit

struct GCodeViewer: View {

    @ObservedObject var model: GCodeStore
    var highlightedLine: Int? = nil

    /// Cached result of `GCodeToolpathAnalyzer.analyze`. This used to be a
    /// computed property, which ran the analyzer — two `NSRegularExpression`
    /// passes over every line in the file — from scratch on every read, and
    /// it's read 3 times in `body` below. Worse, `body` re-evaluates on
    /// *any* `GCodeStore` publish, which includes `scrubLine`/`requestedLine`
    /// changing on every single scrub-slider tick. So dragging the scrubber
    /// was re-running a full-file regex scan, up to 3x, per tick — on a
    /// large file that's almost certainly the dominant cost, well above
    /// anything happening on the Metal side. Recomputed only when the
    /// file's lines actually change (`refreshToolpaths`), not on scrub.
    @State private var toolpaths: [GCodeToolpath] = []

    var body: some View {
        VStack(spacing: 4) {
            toolpathsView
                .background(Color(.white))
                .frame(height: 200)
            GCodeTableView(document: model.document, highlightedLine: highlightedLine, requestedLine: model.requestedLine)
            commandBar
                .frame(height: 36)
        }
        .onAppear {
            refreshToolpaths()
        }
        .onChange(of: model.document.lines.count) { _, newCount in
            if model.analyzedLineCount != newCount {
                model.analyzedLineCount = newCount
                model.selectedToolpathID = nil
            }
            refreshToolpaths()
        }
        .onChange(of: model.document.toolpathSegments.count) { _, _ in
            // Catches in-place line edits that regenerate `toolpathSegments`
            // without changing `lines.count` (e.g. editing one line's G-code
            // text) — those wouldn't otherwise trigger a refresh above.
            refreshToolpaths()
        }
    }

    private func refreshToolpaths() {
        toolpaths = GCodeToolpathAnalyzer.analyze(model.document.lines.map { (id: $0.id, text: $0.text) })
    }

    // MARK: - Toolpaths

    private var toolpathsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Toolpaths")
                    .font(.headline)

                Spacer()

                Text("\(toolpaths.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if toolpaths.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No cutting toolpaths detected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(selection: $model.selectedToolpathID) {
                    ForEach(toolpaths) { toolpath in
                        ToolpathRow(toolpath: toolpath)
                            .tag(toolpath.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.selectedToolpathID = toolpath.id
                                model.requestedLine = toolpath.startLine
                            }
                    }
                }
                .onChange(of: model.selectedToolpathID) { _, newID in
                    guard let newID, let toolpath = toolpaths.first(where: { $0.id == newID }) else {
                        return
                    }
                    model.requestedLine = toolpath.startLine
                }
            }
        }
    }

    private var commandBar: some View {
        HStack(spacing: 8) {
            Button {

            } label: {
                Image(systemName: "pause.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            Button {

            } label: {
                Image(systemName: "stop.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            Button {

            } label: {
                Image(systemName: "play.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)

            Spacer()

            Button {

            } label: {
                Text("Send to Machine")
            }
//            .disabled(!model.connection.isConnected)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ToolpathRow: View {
    let toolpath: GCodeToolpath

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .frame(width: 18)
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(toolpath.operation)
                        .font(.subheadline)
                        .lineLimit(1)

                    if let tool = toolpath.toolNumber {
                        Text("T\(tool)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                Text("\(toolpath.lineRangeText) · \(toolpath.motionCount) moves")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .help("Jump to \(toolpath.lineRangeText)")
    }

    private var iconName: String {
        if toolpath.operation.hasPrefix("Drilling") {
            return "arrow.down.to.line"
        }
        if toolpath.operation == "Rapid" {
            return "arrow.triangle.turn.up.right.diamond"
        }
        return "scribble.variable"
    }

    private var iconColor: Color {
        if toolpath.operation.hasPrefix("Drilling") {
            return .orange
        }
        if toolpath.operation == "Rapid" {
            return .secondary
        }
        return .accentColor
    }
}
