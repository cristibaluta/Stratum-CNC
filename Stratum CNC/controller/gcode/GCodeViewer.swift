//
//  GCodeViewer.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import SwiftUI
import AppKit
import StratumLink

struct GCodeViewer: View {

    @ObservedObject var model: GCodeStore
    @ObservedObject var uploader: SL.Uploader
    @ObservedObject var connection: SL.Connection
    @ObservedObject var macros: MacroStore

    var mode: GCodePanelMode = .gcode

    var onRunMacro: (([String]) -> Void)? = nil
    var highlightedLine: Int? = nil
    var onLineSelected: ((Int) -> Void)? = nil
    var onPlay: (() -> Void)? = nil
    /// Saves the displayed program to a file the person chooses.
    var onExport: (() -> Void)? = nil
    var onPause: (() -> Void)? = nil
    var onSuspend: (() -> Void)? = nil
    var onResume: (() -> Void)? = nil
    var onResumeFromLine: ((Int) -> Void)? = nil
    var canResumeFromLine: Bool = false
    /// Opens the change-bit-and-resume flow.
    var onChangeBit: (() -> Void)? = nil
    var canChangeBit: Bool = false
    var onStop: (() -> Void)? = nil

    @State private var toolpaths: [GCodeToolpath] = []
    /// Finds a clean line to resume from; rebuilt with the toolpaths.
    @State private var resumeResolver: ResumePointResolver?

    var body: some View {
        VStack(spacing: 4) {
            switch mode {
                case .gcode:
                    toolpathsView
                        .frame(height: 200)
                case .macros:
                    MacrosListView(store: macros)
                        .frame(height: 200)
            }
            if mode == .macros, let macro = macros.selectedMacro {
                MacroDetailView(store: macros,
                                macro: macro,
                                canRun: canRunMacro,
                                onRun: { onRunMacro?($0) })
            }

            Divider()
                .frame(height: 1)

            switch mode {
                case .gcode:
                    GCodeTableView(document: model.document,
                                   highlightedLine: machineLine ?? highlightedLine,
                                   requestedLine: model.requestedLine, onLineSelected: onLineSelected)
                case .macros:
                    // Same table, showing the selected macro's generated G-code.
                    GCodeTableView(document: macros.document,
                                   highlightedLine: nil,
                                   requestedLine: nil, onLineSelected: nil)
            }
            jobProgress

            Divider()

            commandBar
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
            refreshToolpaths()
        }
    }

    private func refreshToolpaths() {
        toolpaths = GCodeToolpathAnalyzer.analyze(model.document.lines.map { (id: $0.id, text: $0.text) })
        resumeResolver = ResumePointResolver(lines: model.document.lines.map(\.text), toolpaths: toolpaths)
    }

    // MARK: - Toolpaths

    private var toolpathsView: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                .scrollContentBackground(.hidden)
                .onChange(of: model.selectedToolpathID) { _, newID in
                    guard let newID, let toolpath = toolpaths.first(where: { $0.id == newID }) else {
                        return
                    }
                    model.requestedLine = toolpath.startLine
                }
            }
        }
    }

    private var machineLine: Int? {
        guard let job = connection.status?.activeJob,
              job.currentLine > 0,
              job.currentLine <= model.document.lines.count
        else { return nil }
        return job.currentLine
    }

    /// The running job's progress bar lives under the canvas, in place of the
    /// scrub slider (`ScrubberOrJobProgress`); this only keeps the summary of
    /// the previous job.
    @ViewBuilder
    private var jobProgress: some View {
        if connection.status?.activeJob == nil, let last = connection.status?.lastJob {
            HStack {
                Text(verbatim: "Last job: line \(last.currentLine)")
                Spacer()
                Text(verbatim: "\(last.percent)% · \(last.elapsedText)")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
        }
    }

    /// A job can be started when there's something to send and nothing
    /// already uploading. Deliberately doesn't require a live connection:
    /// `onPlay` now opens `MachineConnectSheet` when disconnected (see
    /// `ControllerView`), so tapping Play with nothing connected is a
    /// prompt to connect, not a dead click — gating the button itself on
    /// `connection.isConnected` would disable it right when it's needed to
    /// start that flow.
    private var canStartJob: Bool {
        !uploader.isActive && !model.document.lines.isEmpty
    }

    /// Exporting needs a program on screen, and a finished load: while a file is still
    /// parsing, `lines` is the previous program or nothing.
    private var canExport: Bool {
        onExport != nil && !model.document.isLoading && !model.document.lines.isEmpty
    }

    /// A macro streams straight to the machine, so it needs a connection and
    /// nothing else already moving it or uploading.
    private var canRunMacro: Bool {
        connection.isConnected && !uploader.isActive && connection.status?.isBusy != true
    }

    /// Feed-held, per the machine's own status report — so this is also
    /// true for a hold that was started from the machine's controls.
    private var isHeld: Bool {
        connection.status?.isHeld == true
    }

    /// Pause is offered while the machine is moving; resume while it's held.
    private var canPauseOrResume: Bool {
        guard connection.isConnected, let status = connection.status else { return false }
        return status.isRunning || status.isHeld || status.isSuspended
    }

    private var isSuspended: Bool {
        connection.status?.isSuspended == true
    }

    /// Held or suspended: either way the job is waiting for a resume.
    private var isPaused: Bool {
        isHeld || isSuspended
    }

    /// A job is in flight from the first upload byte until it finishes or is
    /// stopped, including while held or suspended. Pause/stop only exist
    /// then; otherwise the bar shows just "Send to Machine".
    private var isJobActive: Bool {
        uploader.isActive || connection.status?.isBusy == true || isPaused
    }

    /// Suspend needs a job that is actually playing and moving, mirroring
    /// `ControllerModel.suspendJob`'s own guard.
    private var canSuspend: Bool {
        guard connection.isConnected, let status = connection.status else { return false }
        return status.isRunning && status.activeJob != nil
    }

    /// Stop covers both an upload in flight and a job running on the
    /// machine, so it's enabled for either.
    private var canStop: Bool {
        uploader.isActive || (connection.isConnected && (connection.status?.isBusy == true || isPaused))
    }

    private var resumeLineTarget: Int? {
        model.requestedLine ?? highlightedLine
    }

    /// The line to resume from: what the person picked (or where the job is),
    /// moved back to the start of the pass it falls in.
    private var resumePoint: ResumePoint? {
        guard let target = resumeLineTarget else { return nil }
        return resumeResolver?.resolve(requestedLine: target)
            ?? ResumePoint(requestedLine: target, line: target, reason: .none)
    }

    private var progressText: String? {
        if connection.status?.isSuspended == true {
            return "Suspended"
        }
        if isHeld {
            return "Paused"
        }
        switch uploader.state {
        case let .transferring(sent, total):
            guard total > 0 else { return "…" }
            let percent = Int((Double(sent) / Double(total)) * 100)
            return "\(percent)%"
        case .arming, .verifying:
            return "…"
        case .completed:
            return "Sent"
        case .failed(let message):
            return "Failed: \(message)"
        case .idle, .cancelled:
            return nil
        }
    }

    private var commandBar: some View {
        HStack(spacing: 8) {
            if isJobActive {
                jobControls
            } else {
                Button {
                    onPlay?()
                } label: {
                    Label("Review & Start...", systemImage: "play.fill")
                }
                .buttonStyle(JobButtonStyle(tint: .green))
                .disabled(!canStartJob)
                .help(connection.isConnected
                      ? "Review and upload the loaded program to the machine's SD card"
                      : "Connect a machine, then review and upload the loaded program")

                Spacer()
                Spacer()

                if canChangeBit {
                    changeBitButton
                }

                Button {
                    onExport?()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .disabled(!canExport)
                .help("Export the G-code shown here to a file")
            }

            if let progressText {
                Spacer()
                Text(progressText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 22)
    }

    @ViewBuilder
    private var jobControls: some View {
        if isPaused, canResumeFromLine, let point = resumePoint {
            Button {
                onResumeFromLine?(point.line)
            } label: {
                Text("Resume from Line \(point.line)")
            }
            .buttonStyle(QuietButtonStyle(tint: .accentColor))
            .help("\(point.explanation) Seeks there (console \"goto \(point.line)\"), then resumes — instead of continuing from where it paused. Lift Z first.")
        }

        // Machine-side controls: not offered while a file is still uploading.
        if canPauseOrResume {
            Button {
                if isPaused {
                    onResume?()
                } else {
                    onPause?()
                }
            } label: {
                Image(systemName: isPaused ? "playpause.fill" : "pause.fill")
            }
            .buttonStyle(QuietButtonStyle(tint: .orange))
            .help(isPaused ? "Resume the job" : "Pause the job — feed hold (!)")

            if canSuspend {
                Button {
                    onSuspend?()
                } label: {
                    Image(systemName: "moon.zzz.fill")
                }
                .buttonStyle(QuietButtonStyle(tint: .secondary))
                .help("Suspend the job to continue later: stops the spindle and saves the position (console suspend). Resume brings it back.")
            }
        }

        Button {
            onStop?()
        } label: {
            Image(systemName: "stop.fill")
        }
        .buttonStyle(QuietButtonStyle(tint: .red))
        .disabled(!canStop)
        .help("Stop: cancels an upload, or aborts the running job with a soft reset (not resumable)")

        if canChangeBit {
            changeBitButton
        }
    }

    private var changeBitButton: some View {
        Button {
            onChangeBit?()
        } label: {
            Image(systemName: "wrench.and.screwdriver.fill")
        }
        .buttonStyle(QuietButtonStyle(tint: .secondary))
        .help("Change the bit and resume the job from where it stopped")
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
        return .secondary
    }
}
