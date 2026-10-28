//
//  HoldingTabsButton.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 27.10.2026.
//
//
//  The contour's holding tabs: a row in the Operation section that only summarises them
//  (read-only text), and the popover it opens, where each tab sits in its own group box.
//  Same pattern as `RampingButton` / `RampingEditor`.
//

import SwiftUI

/// Same look as `RampingButton`: a labelled pop-up button, here showing a summary of the tabs.
struct HoldingTabsButton: View {
    let tabs: [HoldingTabSettings]
    let action: () -> Void

    var body: some View {
        InspectorRow(label: "Tabs") {
            Button(action: action) {
                InspectorMenuLabel {
                    Text(summary)
                        .foregroundStyle(tabs.isEmpty ? .secondary : .primary)
                }
            }
            .buttonStyle(.plain)
            .help("Add, remove and size the holding tabs")
        }
    }

    /// "None", "3 tabs", or "3 tabs · 4 × 1.5 mm" when they are all the same size.
    private var summary: String {
        guard let first = tabs.first else {
            return "None"
        }
        let count = tabs.count == 1 ? "1 tab" : "\(tabs.count) tabs"
        let sameSize = tabs.allSatisfy { $0.width == first.width && $0.height == first.height }
        guard sameSize else {
            return count
        }
        return "\(count) · \(Self.format(first.width)) × \(Self.format(first.height)) mm"
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US")))
    }
}

struct HoldingTabsEditor: View {
    @Binding var tabs: [HoldingTabSettings]

    /// The selected shapes' outlines, built when the popover is drawn. Empty when nothing is
    /// selected (or the facing covers the whole stock): the drawing is then a schematic.
    var shapes: () -> [CGPath] = { [] }

    /// Which of the shapes the drawing shows; one at a time.
    @State private var shapeIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Holding tabs")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    tabs.append(HoldingTabSettings.new(after: tabs))
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if tabs.isEmpty {
                Text("No tabs. The part is cut free of the stock; add tabs to keep it attached.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                positionDrawing
            }

            ForEach(Array($tabs.enumerated()), id: \.element.id) { index, $tab in
                GroupBox {
                    VStack(alignment: .leading, spacing: Inspector.rowSpacing) {
                        InspectorNumberField(title: "Position",
                                             value: clamped($tab.positionRatio, HoldingTabSettings.positionRange),
                                             suffix: "ratio (0-1)")
                            .help("How far along the contour the tab sits, as a fraction of its total length.")
                        InspectorNote(text: String(format: "%.0f %% of the way along the contour, counted from where it starts. 0 and 1 are the same spot.",
                                                   tab.positionRatio * 100))
                        InspectorNumberField(title: "Width",
                                             value: clamped($tab.width, HoldingTabSettings.widthRange),
                                             suffix: "mm")
                            .help("How long the tab is, measured along the contour.")
                        InspectorNumberField(title: "Height",
                                             value: clamped($tab.height, HoldingTabSettings.heightRange),
                                             suffix: "mm")
                            .help("How much material the tab leaves, measured up from the bottom of the cut. The tool rises to this height over the tab.")
                    }
                    .padding(.top, 4)
                } label: {
                    HStack {
                        Text("Tab \(index + 1)")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button {
                            let id = tab.id
                            tabs.removeAll { $0.id == id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Remove this tab")
                    }
                }
            }
        }
        .padding(16)
    }

    /// Where the tabs sit along the contour, since "position" alone doesn't say it: the selected
    /// shape with a numbered marker per tab. With several shapes, one is shown at a time.
    @ViewBuilder
    private var positionDrawing: some View {
        let outlines = shapes()
        let index = min(shapeIndex, max(outlines.count - 1, 0))

        VStack(alignment: .leading, spacing: 6) {
            if outlines.count > 1 {
                HStack(spacing: 8) {
                    Button {
                        shapeIndex = (index + outlines.count - 1) % outlines.count
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)

                    Text("Shape \(index + 1) of \(outlines.count)")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)

                    Button {
                        shapeIndex = (index + 1) % outlines.count
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderless)
                }
            }

            TabPositionDiagram(tabs: tabs, shape: outlines.isEmpty ? nil : outlines[index])

            Text(outlines.isEmpty
                 ? "Schematic. Select the contour on the canvas to see its real shape here."
                 : "Approximate: the tool follows the shape offset by its radius, so real positions shift slightly. 0 → 1 runs along the shape from its start. The same tabs are drawn in purple on the canvas.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The ranges are the limits the engine accepts (see `SC.MachiningOperation.formFields`),
    /// so a typed value is pulled back inside them.
    private func clamped(_ value: Binding<Double>, _ range: ClosedRange<Double>) -> Binding<Double> {
        Binding(get: { value.wrappedValue },
                set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) })
    }
}

#Preview {
    @Previewable @State var tabs = [HoldingTabSettings(positionRatio: 0.25, width: 4, height: 1.5)]
    HoldingTabsEditor(tabs: $tabs)
        .frame(width: 400)
}
