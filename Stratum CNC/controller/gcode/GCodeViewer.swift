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
    /// Owns the play/pause/stop state for the loaded program. Observed
    /// directly (rather than reached through `model`) so this view updates
    /// live as the job progresses — same reasoning as `PanelPosition`
    /// observing `MachineConnection` directly instead of through
    /// `ControllerModel`.
    @ObservedObject var jobRunner: GCodeJobRunner
    /// Observed directly for the same reason as `jobRunner` above — used to
    /// disable "play" while there's nothing to send to.
    @ObservedObject var connection: MachineConnection
    var highlightedLine: Int? = nil
    /// Forwarded straight to `GCodeTableView`'s `onLineSelected` — see there
    /// for what "selected" covers. `ControllerView` supplies the closure
    /// that actually syncs the scrubber and the Metal canvas.
    var onLineSelected: ((Int) -> Void)? = nil
    /// Starts streaming the loaded program. `ControllerView` supplies this
    /// as a closure into `ControllerModel.startJob(lines:)` since this view
    /// only holds the `GCodeStore`, not the machine connection.
    var onPlay: (() -> Void)? = nil
    var onPause: (() -> Void)? = nil
    var onResume: (() -> Void)? = nil
    var onStop: (() -> Void)? = nil

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
            GCodeTableView(document: model.document, highlightedLine: highlightedLine, requestedLine: model.requestedLine, onLineSelected: onLineSelected)
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

    /// A job can be started when there's something to send and nothing
    /// already running. Doesn't require a live connection by itself —
    /// `onPlay` (wired to `ControllerModel.startJob`) is the source of
    /// truth for that and simply no-ops while disconnected — but a visibly
    /// disabled button while disconnected is a clearer signal than a play
    /// tap that silently does nothing.
    private var canStartJob: Bool {
        connection.isConnected && !jobRunner.isActive && !model.document.lines.isEmpty
    }

    private var commandBar: some View {
        HStack(spacing: 8) {
            Button {
                switch jobRunner.state {
                case .paused:
                    onResume?()
                default:
                    onPause?()
                }
            } label: {
                Image(systemName: jobRunner.state == .paused ? "play.fill" : "pause.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!jobRunner.isActive)
            .help(jobRunner.state == .paused ? "Resume the job" : "Pause the job")

            Button {
                onStop?()
            } label: {
                Image(systemName: "stop.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!jobRunner.isActive)
            .help("Stop the job")

            Button {
                onPlay?()
            } label: {
                Image(systemName: "play.fill")
                    .foregroundStyle(canStartJob ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!canStartJob)
            .help("Send the loaded program to the machine")

            Spacer()

            if jobRunner.totalLines > 0 {
                Text("\(jobRunner.linesSent)/\(jobRunner.totalLines)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button {
                onPlay?()
            } label: {
                Text("Send to Machine")
            }
            .disabled(!canStartJob)
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
