//
//  ProbeSheet.swift
//  Stratum CNC
//
//  The guided 3D probing dialog: what to probe → where to jog → probe → result.
//  The rules live in `ProbeFlow`; this only presents them. Steps 1 ("What")
//  2 ("Position"), 3 ("Probe") and 4 ("Result") are all built.
//

import SwiftUI
import StratumLink

struct ProbeSheet: View {

    @ObservedObject var model: ControllerModel
    let geometry: StockGeometry
    /// Observed directly so the live position and the jog pad follow the machine.
    @ObservedObject var connection: SL.Connection

    @Environment(\.dismiss) private var dismiss
    @State private var flow: ProbeFlow
    @State private var isShowingSettings = false
    @StateObject private var sequencer: ProbeSequencer
    /// The checklist on the probe step. Reset whenever the step is entered.
    @State private var checks = Set<Int>()
    @State private var isDryRun = false
    /// Set once Apply has written the origin, so it can be undone.
    @State private var applied: ProbeAppliedOrigin?

    init(model: ControllerModel, geometry: StockGeometry, connection: SL.Connection) {
        self.model = model
        self.geometry = geometry
        self.connection = connection
        _flow = State(initialValue: ProbeFlow(geometry: geometry))
        _sequencer = StateObject(wrappedValue: ProbeSequencer(model: model))
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
                    case .what: whatStep
                    case .position: positionStep
                    case .probe: probeStep
                    case .result: resultStep
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(16)

            Divider()
            footer
        }
        .frame(width: flow.step == .what ? 560 : 780)
        .onChange(of: flow.step) { _, step in
            if step == .probe {
                checks = []
                applied = nil
            }
        }
        .onDisappear { sequencer.stopIfRunning() }
    }

    // MARK: Header / footer

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("3D Probe")
                    .font(.headline)
                Text("\(geometry.displayName) · \(geometry.dimensionsDescription)")
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
            Button(flow.step == .result ? "Done" : "Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Spacer()

            if flow.step != .what {
                Button("Back") {
                    sequencer.reset()
                    flow.goBack()
                }
                .disabled(sequencer.isRunning)
            }
            Button("Next") { flow.advance() }
                .keyboardShortcut(.defaultAction)
                .disabled(!flow.canAdvance || (flow.step == .probe && !canLeaveProbeStep))
        }
        .padding(16)
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(ProbeFlow.Step.allCases, id: \.rawValue) { step in
                let isCurrent = step == flow.step
                let isDone = step.rawValue < flow.step.rawValue
                HStack(spacing: 6) {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "\(step.rawValue + 1).circle\(isCurrent ? ".fill" : "")")
                        .foregroundStyle(isDone ? Color.green : (isCurrent ? Color.accentColor : Color.secondary))
                    Text(step.title)
                        .font(.caption)
                        .foregroundStyle(isCurrent ? .primary : .secondary)
                }
                if step != ProbeFlow.Step.allCases.last {
                    Rectangle().fill(.quaternary).frame(height: 1)
                }
            }
        }
    }

    // MARK: Step 1: what

    private var whatStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What do you want to probe?")
                .font(.subheadline.weight(.medium))

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {
                ForEach(flow.availableKinds) { kind in
                    kindTile(kind)
                }
            }

            if flow.shape == .circle {
                Text("Round stock has no corners or straight sides, so only Z and the center can be probed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if flow.needsCircleSide {
                Picker("Side", selection: $flow.circleSide) {
                    ForEach(CircleSide.allCases) { side in
                        Text(side.title).tag(side)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text(flow.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func kindTile(_ kind: ProbeKind) -> some View {
        let isSelected = kind == flow.kind
        return Button {
            flow.kind = kind
        } label: {
            HStack(spacing: 10) {
                Image(systemName: kind.systemImage)
                    .font(.title2)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.callout.weight(.medium))
                    Text(kind.subtitle(shape: flow.shape))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                              lineWidth: isSelected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: Step 2: position

    private var positionStep: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 8) {
                ProbeStockDiagram(flow: $flow, inset: model.probeSettings.startInset)
                    .frame(minWidth: 360, maxWidth: .infinity, minHeight: 380)

                HStack(spacing: 6) {
                    Image(systemName: "circle.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("\(selectionHint) The dot is where to jog the probe to, not where it is now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                livePosition
                instructionList
                settingsRow
                ProbeJogPad(model: model, connection: connection)
            }
            .frame(width: 280)
        }
    }

    private var selectionHint: String {
        if flow.needsCorner { return "Click a corner to choose it." }
        if flow.needsEdge { return "Click a side to choose it." }
        return ""
    }

    private var livePosition: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("WORK POSITION")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            if let status = connection.status {
                Text(String(format: "X %.3f   Y %.3f   Z %.3f",
                            status.workPosition.x, status.workPosition.y, status.workPosition.z))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            } else {
                Text("Not connected")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var instructionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(flow.instructions(settings: model.probeSettings).enumerated()), id: \.offset) { index, text in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                    Text(text)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var settingsRow: some View {
        let settings = model.probeSettings
        return HStack(alignment: .top, spacing: 8) {
            Text("Safe Z \(ProbeFlow.mm(settings.safeZ)) · feed \(ProbeFlow.mm(settings.searchFeed))/\(ProbeFlow.mm(settings.measureFeed)) mm/min · ball Ø\(ProbeFlow.mm(settings.ballDiameter))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                isShowingSettings.toggle()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.quiet)
            .popover(isPresented: $isShowingSettings, arrowEdge: .bottom) {
                ProbeSettingsView(settings: $model.probeSettings)
            }
        }
    }

    // MARK: Step 3: probe

    private var plan: [ProbeStepPlan] {
        ProbeCycleBuilder(flow: flow,
                          settings: model.probeSettings,
                          zeroZCommand: model.zeroCommand(z: true)).build()
    }

    private static let checklist = [
        "The probe is in the spindle and triggers when I touch the tip.",
        "The spindle is off.",
        "The tip is above the dot and above the stock.",
        "Nothing above the stock is in the probe's way.",
    ]

    private var allChecked: Bool {
        checks.count == Self.checklist.count && model.probeSettings.hasConfirmedBallDiameter
    }

    private var problems: [String] {
        ProbeCycleBuilder.problems(flow: flow, settings: model.probeSettings)
    }

    /// Why Start is disabled, or nil.
    private var startBlocker: String? {
        if let first = problems.first { return first }
        if !allChecked { return "Tick every item first." }
        if !isDryRun, let blocker = sequencer.startBlocker { return blocker }
        return nil
    }

    private var canLeaveProbeStep: Bool {
        sequencer.state == .finished && !sequencer.wasDryRun
    }

    private var probeStep: some View {
        HStack(alignment: .top, spacing: 16) {
            planList
                .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 12) {
                if sequencer.state == .idle || sequencer.state == .stopped || isFailed {
                    checklistView
                }
                runControls
            }
            .frame(width: 300)
        }
    }

    private var isFailed: Bool {
        if case .failed = sequencer.state { return true }
        return false
    }

    private var planList: some View {
        let rows = sequencer.rows.isEmpty
            ? plan.enumerated().map { ProbeSequencer.Row(id: $0.offset, title: $0.element.title) }
            : sequencer.rows

        return VStack(alignment: .leading, spacing: 6) {
            Text("WHAT WILL HAPPEN")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(rows) { row in
                        HStack(alignment: .top, spacing: 8) {
                            rowIcon(row.status)
                                .frame(width: 16, height: 16)
                            Text(row.title)
                                .font(.callout)
                                .foregroundStyle(row.status == .pending ? .secondary : .primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 400)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        }
    }

    @ViewBuilder
    private func rowIcon(_ status: ProbeSequencer.RowStatus) -> some View {
        switch status {
            case .pending:
                Image(systemName: "circle").foregroundStyle(.tertiary)
            case .running:
                ProgressView().controlSize(.small)
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private var checklistView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BEFORE YOU START")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(Self.checklist.enumerated()), id: \.offset) { index, text in
                Toggle(isOn: Binding(
                    get: { checks.contains(index) },
                    set: { if $0 { checks.insert(index) } else { checks.remove(index) } }
                )) {
                    Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
                }
            }

            if !model.probeSettings.hasConfirmedBallDiameter {
                Toggle(isOn: $model.probeSettings.hasConfirmedBallDiameter) {
                    Text("The probe ball is Ø\(ProbeFlow.mm(model.probeSettings.ballDiameter)) mm.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ForEach(problems, id: \.self) { problem in
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var runControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch sequencer.state {
                case .idle, .stopped:
                    Toggle("Dry run: write the G-code to the log, don't move", isOn: $isDryRun)
                        .font(.caption)
                    startButton
                    if let blocker = startBlocker {
                        Text(blocker).font(.caption).foregroundStyle(.secondary)
                    }
                    if sequencer.state == .stopped {
                        Text("Stopped. The machine may need unlocking before the next run.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                case .running:
                    Button(role: .destructive) {
                        sequencer.stop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    Text("Keep a hand near the machine's emergency stop.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .finished:
                    Label(sequencer.wasDryRun ? "Dry run done. See the log." : "Probing finished.",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if sequencer.wasDryRun {
                        Button("Run it for real") { sequencer.reset() }
                    } else {
                        Text("Press Next to see what was measured.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                case let .failed(message):
                    Label("Probing stopped", systemImage: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Unlock the machine") { model.sendRawCommand(model.unlockCommand) }
                        startButton
                    }
            }
        }
    }

    private var startButton: some View {
        Button {
            sequencer.start(plan: plan, dryRun: isDryRun)
        } label: {
            Label(isDryRun ? "Dry run" : "Start probing", systemImage: "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(startBlocker != nil)
    }

    // MARK: Step 4: result

    private var probeResult: ProbeResult {
        let layout = model.scene.machineLayout
        return ProbeResult(flow: flow,
                           settings: model.probeSettings,
                           contacts: sequencer.contacts,
                           bedMin: SIMD2(Double(layout.bedMin.x), Double(layout.bedMin.y)),
                           bedMax: SIMD2(Double(layout.bedMax.x), Double(layout.bedMax.y)))
    }

    private var resultStep: some View {
        let result = probeResult
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                measuredTable(result)
                originBox(result)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(result.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                runStartBox(result)
                applyControls(result)
            }
            .frame(width: 300)
        }
    }

    private func measuredTable(_ result: ProbeResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MEASURED")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if result.rows.isEmpty {
                Text("Nothing was measured.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(result.rows) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.label)
                        .font(.callout)
                    Spacer(minLength: 8)
                    Text(row.value)
                        .font(.system(size: 12, design: .monospaced))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }

    private func originBox(_ result: ProbeResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NEW WORK ORIGIN")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if result.hasOrigin {
                Text(flow.originDescription)
                    .font(.callout)
                let x = result.originX.map { ProbeResult.format($0) } ?? "unchanged"
                let y = result.originY.map { ProbeResult.format($0) } ?? "unchanged"
                Text("Machine X \(x)   Y \(y)")
                    .font(.system(size: 12, design: .monospaced))
            } else if let z = result.surfaceZ {
                Text("Z0 was set on the top of the stock (machine Z \(ProbeResult.format(z))). Nothing else to apply.")
                    .font(.callout)
            } else {
                Text("No origin could be worked out from the measurements.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// What a run would write at its start, next to what was probed. If they
    /// differ, starting a run moves the origin.
    private func runStartBox(_ result: ProbeResult) -> some View {
        let lines = model.runStartLines(forProbed: result, previousOffset: applied?.previousXYOffset ?? model.scene.xyOffset)
        return VStack(alignment: .leading, spacing: 6) {
            Text("AT THE START OF A RUN THE APP SENDS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 11, design: .monospaced))
            }
            if result.hasOrigin, !result.isCarried(by: lines) {
                Label("These numbers are not the origin measured here. That is fine if the machine adds its anchor itself. If not, a run would move the origin.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func applyControls(_ result: ProbeResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let applied {
                Label("Origin written to \(model.probeSettings.workCoordinateSystemName).", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("The canvas job offset moved with it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    if result.originX != nil, result.originY != nil {
                        Button("Move over the origin") { model.moveOverProbedOrigin(result) }
                    }
                    Button("Undo") {
                        model.revertProbedOrigin(applied)
                        self.applied = nil
                    }
                    .disabled(applied.revertCommand == nil && applied.previousXYOffset == model.scene.xyOffset)
                }
                if applied.revertCommand == nil {
                    Text("The origin before probing wasn't known, so Undo only restores the canvas offset.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if result.hasOrigin {
                Button {
                    applied = model.applyProbedOrigin(result,
                                                      workCoordinateSystem: model.probeSettings.workCoordinateSystem,
                                                      previousMachineOrigin: sequencer.originBeforeRun)
                } label: {
                    Label("Apply origin", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(connectionIsBusy)

                Text("Done without applying leaves the origin as it was. Z0 was already set during probing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var connectionIsBusy: Bool {
        guard model.connection.isConnected, let status = model.connection.status else { return true }
        return !status.state.hasPrefix("Idle")
    }
}
