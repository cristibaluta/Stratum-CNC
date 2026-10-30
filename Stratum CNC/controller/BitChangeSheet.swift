//
//  BitChangeSheet.swift
//  Stratum CNC
//
//  Guides changing a bit in the middle of a job and carrying on from where it
//  stopped: stop and unlock the machine, replace the bit (by hand, or with the
//  automatic tool changer), choose the restart point, then resume with a
//  generated file. The rules live in `BitChangeFlow`; this only presents them
//  and sends the commands.
//

import SwiftUI
import StratumLink

struct BitChangeSheet: View {

    @ObservedObject var model: ControllerModel
    @ObservedObject var gCodeModel: GCodeStore
    /// Observed directly so the steps react live to the machine's state.
    @ObservedObject var connection: SL.Connection

    @Environment(\.dismiss) private var dismiss

    @State private var flow = BitChangeFlow(sourceLine: 1)
    @State private var resolver: ResumePointResolver?
    @State private var preview: ResumeFile?
    @State private var resumePoint: ResumePoint?

    @State private var lineText = "1"
    @State private var toolText = "1"
    @State private var backUpText = "\(BitChangeFlow.defaultBackUpMillimeters)"
    @State private var programWarning: String?
    @State private var sourceNote: String?

    private var machine: BitChangeFlow.MachineCondition {
        BitChangeFlow.MachineCondition(machineState: connection.status?.state)
    }

    private var programLines: [String] {
        gCodeModel.document.lines.map(\.text)
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            stepIndicator
                .padding(.horizontal, 16)
                .padding(.top, 12)

            Group {
                switch flow.step {
                case .secure: secureStep
                case .replace: replaceStep
                case .restart: restartStep
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(16)

            Divider()
            footer
        }
        .frame(width: 560)
        .onAppear(perform: setUp)
        .onChange(of: flow) { _, _ in refreshPreview() }
        .onChange(of: lineText) { _, text in
            if let line = Int(text.trimmingCharacters(in: .whitespaces)), line >= 1 {
                flow.sourceLine = min(line, max(1, programLines.count))
            }
        }
        .onChange(of: toolText) { _, text in
            if case .automatic = flow.installation {
                flow.setInstallation(.automatic(tool: Int(text.trimmingCharacters(in: .whitespaces)) ?? 0))
            }
        }
        .onChange(of: backUpText) { _, text in
            if case .backUp = flow.restart, let value = Double(text), value >= 0 {
                flow.restart = .backUp(millimeters: value)
            }
        }
    }

    // MARK: Header / footer

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Change Bit & Resume")
                    .font(.headline)
                Text(gCodeModel.document.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            if let blocker = flow.blocker(machine: machine) {
                Text(blocker)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }

            Spacer()

            if flow.step != .secure {
                Button("Back") { flow.goBack() }
            }
            if flow.step == .restart {
                Button {
                    resume()
                } label: {
                    Label("Resume Job", systemImage: "play.fill")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canResume)
            } else {
                Button("Next") { flow.advance(machine: machine) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!flow.canAdvance(machine: machine))
            }
        }
        .padding(16)
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(BitChangeFlow.Step.allCases, id: \.rawValue) { step in
                let isCurrent = step == flow.step
                let isDone = step.rawValue < flow.step.rawValue
                HStack(spacing: 6) {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "\(step.rawValue + 1).circle\(isCurrent ? ".fill" : "")")
                        .foregroundStyle(isDone ? Color.green : (isCurrent ? Color.accentColor : Color.secondary))
                    Text(step.title)
                        .font(.caption)
                        .foregroundStyle(isCurrent ? .primary : .secondary)
                }
                if step != BitChangeFlow.Step.allCases.last {
                    Rectangle().fill(.quaternary).frame(height: 1)
                }
            }
        }
    }

    // MARK: Step 1: stop

    private var secureStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stop the machine so the bit can be changed safely.")
            HStack(spacing: 8) {
                Image(systemName: machineIcon)
                    .foregroundStyle(machineColor)
                Text(machineText)
            }
            .font(.callout)

            HStack {
                Button("Stop Job", role: .destructive) { model.stopJob() }
                    .disabled(machine != .moving && machine != .suspended)
                    .help("Stops the job with a soft reset. Its position is kept, so it can be resumed from a file.")
                Button("Unlock") { model.sendRawCommand(model.unlockCommand) }
                    .disabled(machine != .alarm)
                Button("Home") { model.sendRawCommand(model.homeCommand) }
                    .disabled(machine != .ready && machine != .alarm)
                    .help("Re-home if the position may have been lost, for example after a reset or a power cycle.")
            }

            Text("Stopping resets the machine. The job's position is saved in the app and the program continues from a generated file, so the spindle, tool and Z are set again from the program's own state.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var machineText: String {
        switch machine {
        case .ready: return "The machine is idle."
        case .moving: return "The machine is running. The spindle may be turning."
        case .suspended: return "The job is suspended on the machine."
        case .alarm: return "The machine is in alarm."
        case .unknown: return connection.isConnected ? "Waiting for the machine's status…" : "Not connected."
        }
    }

    private var machineIcon: String {
        switch machine {
        case .ready: return "checkmark.circle.fill"
        case .moving: return "bolt.fill"
        case .suspended: return "moon.zzz.fill"
        case .alarm: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var machineColor: Color {
        switch machine {
        case .ready: return .green
        case .moving, .alarm: return .orange
        case .suspended: return .blue
        case .unknown: return .secondary
        }
    }

    // MARK: Step 2: replace

    private var isAutomatic: Bool {
        if case .automatic = flow.installation { return true }
        return false
    }

    private var replaceStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: Binding(
                get: { isAutomatic },
                set: { automatic in
                    flow.setInstallation(automatic ? .automatic(tool: Int(toolText) ?? 0) : .byHand)
                }
            )) {
                Text("Replace by hand").tag(false)
                Text("Automatic tool change").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if isAutomatic {
                HStack {
                    Text("Tool")
                    TextField("", text: $toolText)
                        .frame(width: 50)
                        .textFieldStyle(.roundedBorder)
                    Text("(T0 is the wireless probe)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("The resume starts with M6 T\(toolText): the changer fetches the tool and the machine measures it as part of the change.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("1. Loosen collet") { model.sendCommand(CNC.loosenSpindleCollet) }
                            .help("M490.2: loosens the collet and drops the current bit")
                        Button("2. Tighten collet") { model.sendCommand(CNC.tightenSpindleCollet) }
                            .help("M490.1: tightens the collet around the new bit")
                        Button("3. Measure tool length") {
                            model.sendCommand(CNC.calibrateTool)
                            flow.calibrationSent = true
                        }
                        .help("M491: measures the new bit's length and resets its tool length offset")
                    }
                    .disabled(machine != .ready)

                    Text("Put the new bit in, tighten the collet, then measure it. Next unlocks when the machine is idle again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if flow.calibrationSent {
                        Label("Measurement started", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            Toggle("Probe Z again before restarting", isOn: $flow.reprobeZ)
            Text("Probes down at the machine's current XY and zeroes the work Z there. Only when the new bit can't be trusted to be measured against the old one; jog over the stock first.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Step 3: restart

    private var restartStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let sourceNote {
                Text(sourceNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let programWarning {
                Label(programWarning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Stopped at line")
                TextField("", text: $lineText)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                Text("of \(programLines.count)")
                    .foregroundStyle(.secondary)
            }

            Picker("", selection: Binding(
                get: { restartKind },
                set: { setRestartKind($0) }
            )) {
                Text("Start of pass").tag(RestartKind.passStart)
                Text("Back up").tag(RestartKind.backUp)
                Text("Exact line").tag(RestartKind.exactLine)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if restartKind == .backUp {
                HStack {
                    Text("Back up")
                    TextField("", text: $backUpText)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                    Text("mm along the cut")
                        .foregroundStyle(.secondary)
                }
            }

            if let resumePoint {
                Text("Resumes from line \(resumePoint.line). \(resumePoint.explanation)")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            preambleView
        }
    }

    private enum RestartKind: Hashable { case passStart, backUp, exactLine }

    private var restartKind: RestartKind {
        switch flow.restart {
        case .passStart: return .passStart
        case .backUp: return .backUp
        case .exactLine: return .exactLine
        }
    }

    private func setRestartKind(_ kind: RestartKind) {
        switch kind {
        case .passStart: flow.restart = .passStart
        case .backUp: flow.restart = .backUp(millimeters: Double(backUpText) ?? BitChangeFlow.defaultBackUpMillimeters)
        case .exactLine: flow.restart = .exactLine
        }
    }

    @ViewBuilder
    private var preambleView: some View {
        if let preview {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(preview.preamble.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(preview.preamble.canResume ? .orange : .red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Before the program continues, the machine is sent:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(preview.preamble.lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(line.hasPrefix(";") ? .secondary : .primary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .frame(height: 140)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: Logic

    private var canResume: Bool {
        machine == .ready && (preview?.preamble.canResume ?? false)
    }

    private func setUp() {
        let lines = programLines
        let toolpaths = GCodeToolpathAnalyzer.analyze(gCodeModel.document.lines.map { (id: $0.id, text: $0.text) })
        resolver = ResumePointResolver(lines: lines, toolpaths: toolpaths)

        // Where the job stopped: what the app saved, else what the canvas shows.
        var line = 1
        let progress = model.job.progress
        if let progress, progress.sourceLine > 0 {
            line = progress.sourceLine
            sourceNote = "Taken from the saved job progress (\(progress.percent)%)."
            if progress.lineOffset == nil, let saved = progress.fingerprint {
                let current = ControllerModel.fingerprint(
                    fileName: gCodeModel.document.fileName,
                    contents: lines.joined(separator: "\n")
                )
                if current != saved {
                    programWarning = "The loaded program is not the one that was running. Check the line before resuming."
                }
            }
        } else if let requested = gCodeModel.requestedLine {
            line = requested
            sourceNote = "No saved job progress: the line was taken from the line selected in the program."
        } else if gCodeModel.scrubLine > 0 {
            line = gCodeModel.scrubLine
            sourceNote = "No saved job progress: the line was taken from the scrubber."
        } else {
            sourceNote = "No saved job progress: choose the line the job stopped at."
        }

        line = min(max(1, line), max(1, lines.count))
        flow = BitChangeFlow(sourceLine: line)
        lineText = "\(line)"

        // Suggest the tool the program had selected at that line.
        if let tool = GCodeModalState.scan(lines: lines, beforeLine: line).state.tool {
            toolText = "\(tool)"
        }
        refreshPreview()
    }

    private func refreshPreview() {
        guard let resolver else { return }
        let point = flow.resumePoint(using: resolver)
        resumePoint = point
        preview = ResumeFileBuilder.build(lines: programLines,
                                          resumeLine: point.line,
                                          options: flow.resumeOptions())
    }

    private func resume() {
        guard let point = resumePoint, canResume else { return }
        model.resumeJobWithGeneratedFile(programLines: programLines,
                                         fileName: gCodeModel.document.fileName,
                                         fromLine: point.line,
                                         resumeOptions: flow.resumeOptions(),
                                         reprobeZ: flow.reprobeZ)
        dismiss()
    }
}
