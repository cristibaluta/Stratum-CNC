//
//  ProbeSheet.swift
//  Stratum CNC
//
//  The guided 3D probing dialog: what to probe (Z, or XY: a boss or pocket
//  corner or center, drawn as 2D tiles) → where to jog (and which corner,
//  chosen on the drawing) → probe → result. No sizes are asked for.
//  The rules live in `ProbeFlow`; this only presents them. Steps 1 ("What")
//  2 ("Position"), 3 ("Probe") and 4 ("Result") are all built.
//

import SwiftUI
import StratumLink

struct ProbeSheet: View {

    @ObservedObject var model: ControllerModel
    /// Kept so the call site does not change. The probe does not use the stock.
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
        _flow = State(initialValue: ProbeFlow())
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
                    case .tool: toolStep
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
        .frame(width: flow.step == .what || flow.step == .tool ? 560 : 780)
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
            Text("3D Probe")
                .font(.headline)
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
            Button("Next") {
                if flow.step == .tool {
                    // The ball diameter was on screen: it counts as confirmed.
                    model.probeSettings.hasConfirmedBallDiameter = true
                }
                flow.advance()
            }
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
        VStack(alignment: .leading, spacing: 16) {
            Picker("Probe", selection: $flow.kind) {
                ForEach(ProbeKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch flow.kind {
                case .zSurface:
                    zTile
                case .point:
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                              spacing: 12) {
                        ForEach(ProbeFeature.allCases) { feature in
                            featureTile(feature)
                        }
                    }
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

    private static let tileShape = RoundedRectangle(cornerRadius: 10)

    // MARK: Step 2: probe

    private var toolStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ForEach(ProbeHardware.allCases) { hardware in
                    hardwareTile(hardware)
                }
            }

            if flow.kind == .point {
                MeasurementField(title: "Probe diameter", value: $model.probeSettings.ballDiameter, unit: "mm")
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text(model.probeSettings.probe.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func hardwareTile(_ hardware: ProbeHardware) -> some View {
        let isSelected = hardware == model.probeSettings.probe
        return Button {
            model.probeSettings.hardware = hardware
        } label: {
            VStack(spacing: 8) {
                ProbeHardwareDrawing(hardware: hardware)
                    .frame(height: 130)
                    .background(Self.tileShape.fill(Color.primary.opacity(0.05)))
                    .overlay(Self.tileShape.strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                                                         lineWidth: isSelected ? 2 : 1))
                VStack(spacing: 2) {
                    Text(hardware.title)
                        .font(.callout.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    Text(hardware.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    /// Z has nothing to choose: one drawing and a sentence.
    private var zTile: some View {
        VStack(spacing: 8) {
            ProbeZDrawing()
                .frame(height: 150)
                .background(Self.tileShape.fill(Color.primary.opacity(0.05)))
                .overlay(Self.tileShape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            Text("Find Z Surface")
                .font(.callout.weight(.medium))
        }
        .frame(maxWidth: 260)
        .frame(maxWidth: .infinity)
    }

    private func featureTile(_ feature: ProbeFeature) -> some View {
        let isSelected = feature == flow.feature
        return Button {
            flow.feature = feature
        } label: {
            VStack(spacing: 8) {
                ProbeFeatureDrawing(feature: feature, corner: .bottomLeft)
                    .frame(height: 130)
                    .background(Self.tileShape.fill(Color.primary.opacity(0.05)))
                    .overlay(Self.tileShape.strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                                                         lineWidth: isSelected ? 2 : 1))
                Text(feature.title)
                    .font(.callout.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Step 3: position

    private var positionStep: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 8) {
                ProbeStockDiagram(flow: $flow)
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
        flow.choosesCorner ? "Click a corner to choose it." : ""
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

    // MARK: Step 4: run

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

    // MARK: Step 5: result

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
                Text("Z0 was set on \(flow.kind == .zSurface ? "the surface under the tip" : (flow.isInside ? "the floor of the pocket" : "the top of the boss")) (machine Z \(ProbeResult.format(z))). Nothing else to apply.")
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

                Text("Done without applying leaves the origin as it was. \(flow.setsZ(settings: model.probeSettings) ? "Z0 was already set during probing." : "Z0 was not changed.")")
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
