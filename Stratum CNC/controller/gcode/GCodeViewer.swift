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
    /// Owns the upload/progress state for the loaded program. Observed
    /// directly (rather than reached through `model`) so this view updates
    /// live as the transfer progresses — same reasoning as `PanelPosition`
    /// observing `MachineConnection` directly instead of through
    /// `ControllerModel`. Real jobs go through here, not `GCodeJobRunner` —
    /// see `GCodeUploader`'s doc comment for why (Roadmap 1.2).
    @ObservedObject var uploader: GCodeUploader
    /// Observed directly for the same reason as `uploader` above — used to
    /// disable "play" while there's nothing to send to.
    @ObservedObject var connection: MachineConnection
    var highlightedLine: Int? = nil
    /// Forwarded straight to `GCodeTableView`'s `onLineSelected` — see there
    /// for what "selected" covers. `ControllerView` supplies the closure
    /// that actually syncs the scrubber and the Metal canvas.
    var onLineSelected: ((Int) -> Void)? = nil
    /// Uploads the loaded program to the machine's SD card. `ControllerView`
    /// supplies this as a closure into `ControllerModel.uploadJob(fileName:
    /// contents:)` since this view only holds the `GCodeStore`, not the
    /// machine connection.
    var onPlay: (() -> Void)? = nil
    /// Feed-hold (`!`) on a job running on the machine. `ControllerModel`
    /// supplies `pauseJob`, which also gates on the machine's reported state
    /// (Roadmap 1.3).
    var onPause: (() -> Void)? = nil
    /// Suspends the job so it can be continued later (console `suspend`):
    /// stops the spindle and saves the position, unlike `onPause`'s
    /// momentary feed-hold. Supplied as `ControllerModel.suspendJob`.
    var onSuspend: (() -> Void)? = nil
    /// Resume after either kind of pause. Supplied as `resumeJob`, which
    /// picks `~` for a feed-hold or `resume` for a suspend.
    var onResume: (() -> Void)? = nil
    /// Resume, but seek to a chosen line first (`goto <line>`, Roadmap 1.5)
    /// instead of continuing from wherever the hold happened. Supplied as
    /// `ControllerModel.resumeJob(fromLine:)`. Only offered once there's a
    /// known SD-card path to seek in — see `canResumeFromLine`.
    var onResumeFromLine: ((Int) -> Void)? = nil
    /// Whether `onResumeFromLine` has anything to seek in — mirrors
    /// `ControllerModel.lastUploadedRemotePath != nil`. `GCodeViewer` has no
    /// other way to know this, since the remote path lives on `uploader`
    /// only transiently (its `.completed` case), not as a standing property.
    var canResumeFromLine: Bool = false
    /// Cancels an in-progress upload, or aborts a job running on the
    /// machine (soft-reset). Supplied as `ControllerModel.stopJob`, which
    /// works out which of the two applies.
    var onStop: (() -> Void)? = nil

    @State private var toolpaths: [GCodeToolpath] = []

    var body: some View {
        VStack(spacing: 4) {
            toolpathsView
                .frame(height: 200)
            GCodeTableView(document: model.document,
                           highlightedLine: machineLine ?? highlightedLine,
                           requestedLine: model.requestedLine, onLineSelected: onLineSelected)
            jobProgress
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

    // MARK: - Job progress (Roadmap 1.4)

    /// The line the machine is executing while a job is running or paused,
    /// in the same 1-based numbering as the table's rows. While a job is
    /// active this takes over the table's highlight — and its
    /// auto-scroll — from the scrubber; when it ends, the highlight goes
    /// back to `highlightedLine`.
    ///
    /// The status report doesn't say *which* file is playing, so this assumes
    /// it's the one loaded here — true after "Send to Machine", not if a job
    /// was started from the machine itself. A line past the end of the loaded
    /// document is ignored rather than highlighted.
    private var machineLine: Int? {
        guard let job = connection.status?.activeJob,
              job.currentLine > 0,
              job.currentLine <= model.document.lines.count
        else { return nil }
        return job.currentLine
    }

    /// Live progress bar for a running/paused job; for a job that has ended,
    /// a quiet line saying where it got to (the firmware keeps reporting it).
    /// Nothing at all before any job has run.
    @ViewBuilder
    private var jobProgress: some View {
        if let job = connection.status?.activeJob {
            VStack(alignment: .leading, spacing: 3) {
                ProgressView(value: job.fraction)
                    .progressViewStyle(.linear)
                HStack {
                    Text(verbatim: "Line \(job.currentLine)")
                    Spacer()
                    Text(verbatim: "\(job.percent)% · \(job.elapsedText)")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        } else if let last = connection.status?.lastJob {
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

    /// Feed-held, per the machine's own status report — so this is also
    /// true for a hold that was started from the machine's controls.
    private var isHeld: Bool {
        connection.status?.isHeld == true
    }

    /// Pause is offered while the machine is moving; resume while it's held.
    private var canPauseOrResume: Bool {
        guard connection.isConnected, let status = connection.status else { return false }
        return status.isRunning || status.isHeld
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
        uploader.isActive || (connection.isConnected && connection.status?.isBusy == true)
    }

    /// The line `onResumeFromLine` would seek to if tapped right now —
    /// whichever row was last tapped in the table (`model.requestedLine`),
    /// falling back to the scrub position passed in as `highlightedLine` so
    /// there's still a sensible target before the user has picked one.
    private var resumeLineTarget: Int? {
        model.requestedLine ?? highlightedLine
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
            // One button, two roles: feed-hold while the machine is running,
            // resume while it's held. Driven by the machine's reported state
            // (polled once a second), so the icon can lag a press by up to a
            // second.
            Button {
                if isHeld {
                    onResume?()
                } else {
                    onPause?()
                }
            } label: {
                Image(systemName: isHeld ? "playpause.fill" : "pause.fill")
                    .foregroundStyle(isHeld ? Color.orange : .secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!canPauseOrResume)
            .help(isHeld ? "Resume the job" : "Pause the job — feed hold (!)")

            Button {
                onSuspend?()
            } label: {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!canSuspend)
            .help("Suspend the job to continue later: stops the spindle and saves the position (console suspend). Resume brings it back.")

            Button {
                onStop?()
            } label: {
                Image(systemName: "stop.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!canStop)
            .help("Stop: cancels an upload, or aborts the running job with a soft reset (not resumable)")

            Button {
                onPlay?()
            } label: {
                Image(systemName: "play.fill")
                    .foregroundStyle(canStartJob ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!canStartJob)
            .help(connection.isConnected
                  ? "Review and upload the loaded program to the machine's SD card"
                  : "Connect a machine, then review and upload the loaded program")

            Spacer()

            if let progressText {
                Text(progressText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Only while held, and only once there's a known SD-card file
            // to seek in — see `canResumeFromLine`. Tap a row in the table
            // above first to change `resumeLineTarget`; this always shows
            // *some* line so there's no dead click, but it's the same line
            // plain "resume" would use until a row is tapped.
            if isHeld, canResumeFromLine, let target = resumeLineTarget {
                Button {
                    onResumeFromLine?(target)
                } label: {
                    Text("Resume from Line \(target)")
                }
                .help("Seek to line \(target) (console \"goto \(target)\"), then resume — instead of continuing from where it paused")
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
