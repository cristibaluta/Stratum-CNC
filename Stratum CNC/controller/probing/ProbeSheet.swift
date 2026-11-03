//
//  ProbeSheet.swift
//  Stratum CNC
//
//  The guided 3D probing dialog: what to probe → where to jog → probe → result.
//  The rules live in `ProbeFlow`; this only presents them. Step 1 ("What")
//  is built; the others are placeholders until their milestones.
//

import SwiftUI

struct ProbeSheet: View {

    @ObservedObject var model: ControllerModel
    let geometry: StockGeometry

    @Environment(\.dismiss) private var dismiss
    @State private var flow: ProbeFlow

    init(model: ControllerModel, geometry: StockGeometry) {
        self.model = model
        self.geometry = geometry
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
                    case .position: placeholderStep("Position", "The stock drawing with the pulsing dot, and a jog pad.")
                    case .probe: placeholderStep("Probe", "The safety checklist and the probing moves.")
                    case .result: placeholderStep("Result", "Measured values, the stock check and Apply.")
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(16)

            Divider()
            footer
        }
        .frame(width: 560)
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

    private var shapeBinding: Binding<ProbeShape> {
        Binding(get: { flow.shape }, set: { flow.setShape($0) })
    }

    private var whatStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What do you want to probe?")
                .font(.subheadline.weight(.medium))

            VStack(alignment: .leading, spacing: 6) {
                Picker("Shape", selection: shapeBinding) {
                    ForEach(ProbeShape.allCases) { shape in
                        Text(shape.title).tag(shape)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(shapeHint)
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

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {
                ForEach(flow.availableKinds) { kind in
                    kindTile(kind)
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

    private var shapeHint: String {
        switch flow.shape {
            case .rectangle: "Stock with straight sides: the top and the sides are touched."
            case .circle: "Round stock or a hole: the center is found from four touches."
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
