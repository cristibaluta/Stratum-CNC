//
//  ProbeSheet.swift
//  Stratum CNC
//
//  The guided 3D probing dialog: what to probe → where to jog → probe → result.
//  The rules live in `ProbeFlow`; this only presents them. Steps 1 ("What")
//  and 2 ("Position") are built; the others are placeholders until their
//  milestones.
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

    init(model: ControllerModel, geometry: StockGeometry, connection: SL.Connection) {
        self.model = model
        self.geometry = geometry
        self.connection = connection
        _flow = State(initialValue: ProbeFlow(geometry: geometry))
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
                    case .probe: placeholderStep("Probe", "The safety checklist and the probing moves.")
                    case .result: placeholderStep("Result", "Measured values, the stock check and Apply.")
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(16)

            Divider()
            footer
        }
        .frame(width: flow.step == .what ? 560 : 780)
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
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Spacer()

            if flow.step != .what {
                Button("Back") { flow.goBack() }
            }
            Button("Next") { flow.advance() }
                .keyboardShortcut(.defaultAction)
                .disabled(!flow.canAdvance)
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

    // MARK: Other steps (not built yet)

    private func placeholderStep(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "hammer")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("\(title) isn't built yet")
                .font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}
