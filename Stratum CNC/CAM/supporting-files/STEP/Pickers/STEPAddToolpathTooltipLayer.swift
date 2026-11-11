//
//  STEPAddToolpathTooltipLayer.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 08.11.2026.
//

import SwiftUI
import SwiftSTEP
import StratumCAM

/// The callout over the selected STEP edges: "Select linked" and "Add toolpath" on top, always
/// there (disabled when they do not apply), and under them one line with what is selected.
/// "Add toolpath" first lists the operations that fit the selection; the toolpath is only created
/// once one is chosen. It sits above the selected feature, at the top of the model, and follows
/// as the camera orbits, pans and zooms.
struct STEPAddToolpathTooltipLayer: View {

    @ObservedObject var scene: STEPDocumentScene
    let zoomModel: CanvasZoomModel
    let canAdd: Bool
    /// An operation was chosen from the list: create the toolpath with it.
    let onChoose: (SC.MachiningOperation.Kind) -> Void

    @State private var frameTick = 0
    /// The callout's own height (its arrow included), so it can be kept below the top edge.
    @State private var calloutHeight: CGFloat = 0

    private static let gap: CGFloat = 6
    /// Space kept between the top of the screen and the top of the callout.
    private static let topPadding: CGFloat = 12
    /// Half the callout's width or more, so it is never cut off at the sides of the canvas.
    private static let horizontalMargin: CGFloat = 220

    var body: some View {
        let _ = frameTick
        GeometryReader { proxy in
            if !scene.selectedEdges.isEmpty, let anchor = anchor(in: proxy.size) {
                STEPSelectionCallout(summary: Self.summary(for: scene),
                                     canSelectLinked: scene.canSelectLinkedInPlane,
                                     canSelectSimilar: scene.canSelectSimilarHoles,
                                     canAdd: canAdd,
                                     operations: scene.availableOperations,
                                     selection: scene.selectedEdges,
                                     onSelectLinked: { scene.selectLinkedEdgesInPlane() },
                                     onSelectSimilar: { scene.selectSimilarHoles() },
                                     onChoose: onChoose)
                    .fixedSize()
                    .background {
                        GeometryReader { callout in
                            Color.clear.preference(key: CalloutHeightKey.self, value: callout.size.height)
                        }
                    }
                    .frame(width: 0, height: 0, alignment: .bottom)
                    .position(anchor)
                    .transition(.opacity)
            }
        }
        .onPreferenceChange(CalloutHeightKey.self) { calloutHeight = $0 }
        .onReceive(zoomModel.frameRendered.receive(on: DispatchQueue.main)) { _ in
            frameTick &+= 1
        }
    }

    /// Where the arrow points: horizontally the centre of the selected feature, vertically the top
    /// of the whole model (its highest corner on screen), so the callout stays at one height while
    /// features are picked. Held `topPadding` below the top edge (the whole callout, not just its
    /// arrow), so it never leaves the screen.
    private func anchor(in size: CGSize) -> CGPoint? {
        guard let box = scene.selectionBox, size.width > 0, size.height > 0 else {
            return nil
        }
        func corners(of box: (min: SIMD3<Float>, max: SIMD3<Float>)) -> [CGPoint] {
            var projected: [CGPoint] = []
            for x in [box.min.x, box.max.x] {
                for y in [box.min.y, box.max.y] {
                    for z in [box.min.z, box.max.z] {
                        if let point = zoomModel.normalizedViewPoint(forWorld: SIMD3<Float>(x, y, z)) {
                            projected.append(point)
                        }
                    }
                }
            }
            return projected
        }
        let feature = corners(of: box)
        guard let left = feature.map(\.x).min(),
              let right = feature.map(\.x).max() else {
            return nil
        }
        // The model's top; the feature's own top when the model has no bounds.
        let top = corners(of: scene.modelBox ?? box).map(\.y).min() ?? feature.map(\.y).min() ?? 0
        let margin = min(Self.horizontalMargin, size.width / 2)
        let x = min(max((left + right) / 2 * size.width, margin), size.width - margin)
        let y = max(top * size.height - Self.gap, calloutHeight + Self.topPadding)

        return CGPoint(x: x, y: y)
    }

    /// One line: how many edges, how far they are from z0, and their size. Each value has its
    /// symbol: Z height relative to z0 (negative is below it), Ø diameter of a circle, R radius
    /// of an arc, L length (of a line, or of all the edges together when there are several, an
    /// arc then counting by its length).
    static func summary(for scene: STEPDocumentScene) -> String {
        func mm(_ value: Float) -> String {
            value.fixed(3)
        }
        let count = scene.selectedEdges.count
        var parts = [count == 1 ? "1 edge" : "\(count) edges"]
        if let z = scene.selectionZRange {
            parts.append(z.upperBound - z.lowerBound < 1e-3
                         ? "Z \(mm(z.lowerBound))"
                         : "Z \(mm(z.lowerBound)) … \(mm(z.upperBound))")
        }
        let measures = scene.selectionMeasures
        if measures.count == 1, let measure = measures.first {
            switch measure.kind {
                case .line, .curve: parts.append("L \(mm(measure.length))")
                case .arc:          parts.append("R \(mm(measure.radius ?? 0))")
                case .circle:       parts.append("Ø \(mm((measure.radius ?? 0) * 2))")
            }
        } else if measures.count > 1 {
            // Circles of one size, or arcs of one radius: that size says more than the total length.
            if let first = measures.first,
                let radius = first.radius,
                first.kind == .circle ||
                first.kind == .arc,
                measures.allSatisfy({ $0.kind == first.kind && abs(($0.radius ?? -1) - radius) <= 0.001 }) {
                parts.append(first.kind == .circle ? "Ø \(mm(radius * 2))" : "R \(mm(radius))")
            } else {
                parts.append("L \(mm(measures.reduce(Float(0)) { $0 + $1.length }))")
            }
        }
        return parts.joined(separator: "  ·  ") + " mm"
    }
}

private struct CalloutHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The callout of the selected STEP edges: the two actions, then one line of numbers.
private struct STEPSelectionCallout: View {

    let summary: String
    let canSelectLinked: Bool
    let canSelectSimilar: Bool
    let canAdd: Bool
    /// The operations that fit the selection.
    let operations: [SC.MachiningOperation.Kind]
    /// The selected edges: choosing is dropped when they change.
    let selection: Set<STEP.EdgeID>
    let onSelectLinked: () -> Void
    let onSelectSimilar: () -> Void
    let onChoose: (SC.MachiningOperation.Kind) -> Void

    /// "Add toolpath" was pressed: the list of operations replaces the buttons.
    @State private var isChoosing = false

    private static let arrowSize = CGSize(width: 16, height: 8)

    var body: some View {
        VStack(spacing: 8) {
            if isChoosing {
                operationList
            } else {
                actions
            }

            Text(summary)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .help("Z: height relative to z0 (negative is below)  ·  Ø: diameter  ·  R: radius  ·  L: length")
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8 + Self.arrowSize.height)
        .background {
            CalloutShape(arrowSize: Self.arrowSize)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .overlay {
            CalloutShape(arrowSize: Self.arrowSize)
                .stroke(.separator)
        }
        .onChange(of: selection) { _, _ in isChoosing = false }
    }

    /// What can be done with the selection: the operations that fit it, one per row.
    private var operationList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Choose an operation")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(operations) { kind in
                Button {
                    isChoosing = false
                    onChoose(kind)
                } label: {
                    Label(kind.title, systemImage: kind.symbol)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .help(kind.summary)
            }
            // Any other operation: the toolpath opens with the first one, to change in its details.
            if let first = operations.first {
                Button {
                    isChoosing = false
                    onChoose(first)
                } label: {
                    Label("Other", systemImage: "ellipsis")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .help("Create the toolpath and choose its operation in the details")
            }
            Button("Cancel") { isChoosing = false }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.small)
        .frame(minWidth: 190)
        .fixedSize()
    }

    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: onSelectLinked) {
                    Label("Select linked", systemImage: "square.dashed")
                }
                .buttonStyle(.bordered)
                .disabled(!canSelectLinked)
                .help(canSelectLinked
                      ? "Also select every edge connected to the selection that lies in the same plane"
                      : "Nothing to add: no other edge in the selection's plane is connected to it")
                Button(action: onSelectSimilar) {
                    Label("Select similar", systemImage: "circle.grid.2x2")
                }
                .buttonStyle(.bordered)
                .disabled(!canSelectSimilar)
                .help(canSelectSimilar
                      ? "Also select the holes with the same diameter and depth as the selected ones"
                      : "Select a hole's circle to find the holes like it")
                Button { isChoosing = true } label: {
                    Label("Add toolpath…", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdd || operations.isEmpty)
            }
            .controlSize(.small)
            .fixedSize()
        }
    }
}
