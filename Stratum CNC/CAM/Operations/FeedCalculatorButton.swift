//
//  FeedCalculatorButton.swift
//  Stratum CNC
//
//  A small calculator icon after the feed rate field. It opens a popover with the formula
//  feed = chip load × flutes × RPM, filled in from the tool and the toolpath where they have
//  the values. Every value can be edited there to see what feed it gives; the toolpath's feed
//  rate only changes when "Use value" is pressed.
//
//  The popover also draws the cut with the glyph of the direction picker, at the real chip
//  load and stepover, and warms its color from green to red as the chip gets too thin (the
//  tool rubs and the heat stays in it) or the spindle too fast. See `ChipLoadAnalysis`.
//

import SwiftUI
import StratumCAM

struct FeedCalculatorButton: View {

    @Binding var toolpath: ToolpathData
    /// The cut direction the glyph shows. Operations that have no climb / conventional choice
    /// leave it at climb.
    var direction: SC.CutDirection = .climb
    /// Whether the operation has a stepover to take into account (chip thinning).
    var usesStepover: Bool = true
    /// The stock being cut, which picks the tool's preset the chip load and surface speed come
    /// from. Without it the first preset that has a chip load is used.
    var stockMaterial: StockMaterialType? = nil

    @State private var isPresented = false

    /// The preset the calculator starts from: the tool's preset for the stock material (see
    /// `Tool.preset(for:)`), so a tool with one preset per material doesn't offer the aluminum
    /// chip load for wood.
    private var preset: ToolPreset? {
        guard let stockMaterial else {
            return toolpath.tool.presets.first { ($0.feedPerTooth ?? 0) > 0 }
        }
        return toolpath.tool.preset(for: stockMaterial)
    }

    /// The preset's chip load (mm per tooth). A preset that only has a feed and a spindle speed
    /// gives it as feed / (flutes × RPM).
    private var presetChipLoad: Double? {
        guard let preset else {
            return nil
        }
        if let chipLoad = preset.feedPerTooth, chipLoad > 0 {
            return chipLoad
        }
        let flutes = Double(toolpath.tool.numberOfFlutes ?? 0)
        if let feed = preset.feedRate, let rpm = preset.spindleRPM, feed > 0, rpm > 0, flutes > 0 {
            return (feed / (flutes * Double(rpm)) * 10_000).rounded() / 10_000
        }
        return nil
    }

    private var presetSurfaceSpeed: Double? {
        preset?.surfaceSpeed.flatMap { $0 > 0 ? $0 : nil }
    }

    var body: some View {
        HoverIconButton {
            isPresented = true
        } label: {
            Image(systemName: "function")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 24)
        }
        // In the compact XY row the buttons share the width with the fields: without this the
        // icon is the first thing to be squeezed out.
        .fixedSize()
        .layoutPriority(1)
        .help("Calculate the feed rate from chip load, flutes and RPM")
        .popover(isPresented: $isPresented, arrowEdge: .leading) {
            FeedCalculatorView(
                chipLoad: initialChipLoad,
                flutes: toolpath.tool.numberOfFlutes ?? 0,
                rpm: toolpath.spindleRPM,
                stepOver: toolpath.stepOverPercent,
                usesStepover: usesStepover,
                toolDiameter: Double(toolpath.tool.toolDiameter),
                stepDown: toolpath.stepDown,
                direction: direction,
                recommendedChipLoad: presetChipLoad,
                recommendedSurfaceSpeed: presetSurfaceSpeed,
                currentFeed: toolpath.feedRate,
                toolHasFlutes: (toolpath.tool.numberOfFlutes ?? 0) > 0
            ) { feed in
                toolpath.feedRate = feed
                isPresented = false
            }
        }
    }

    /// The chip load (mm per tooth) to start from: the one of the tool's preset for the stock,
    /// otherwise what the current feed works out to when the flutes and RPM are known, otherwise 0.
    private var initialChipLoad: Double {
        if let presetChipLoad {
            return presetChipLoad
        }
        let flutes = Double(toolpath.tool.numberOfFlutes ?? 0)
        let rpm = Double(toolpath.spindleRPM)
        if flutes > 0, rpm > 0, toolpath.feedRate > 0 {
            return (toolpath.feedRate / (flutes * rpm) * 10_000).rounded() / 10_000
        }
        return 0
    }
}

private struct FeedCalculatorView: View {

    @State var chipLoad: Double
    @State var flutes: Int
    @State var rpm: Int
    @State var stepOver: Double
    let usesStepover: Bool
    let toolDiameter: Double
    let stepDown: Double
    let direction: SC.CutDirection
    let recommendedChipLoad: Double?
    let recommendedSurfaceSpeed: Double?
    let currentFeed: Double
    let toolHasFlutes: Bool
    let onUse: (Double) -> Void

    /// Everything the numbers say about the cut, recomputed on every keystroke.
    private var analysis: ChipLoadAnalysis {
        ChipLoadAnalysis(chipLoad: chipLoad,
                         flutes: flutes,
                         rpm: rpm,
                         toolDiameter: toolDiameter,
                         stepOverFraction: usesStepover ? stepOver / 100 : nil,
                         stepDown: stepDown,
                         recommendedChipLoad: recommendedChipLoad,
                         recommendedSurfaceSpeed: recommendedSurfaceSpeed)
    }

    private var feed: Double {
        analysis.feed
    }

    private var canUse: Bool {
        feed > 0 && feed != currentFeed
    }

    var body: some View {
        let analysis = self.analysis

        return VStack(alignment: .leading, spacing: Inspector.rowSpacing) {
            Text("Feed rate calculator")
                .font(.system(size: 13, weight: .semibold))

            Text("Feed = chip load × flutes × RPM")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            cutDrawing(analysis)

            row("Chip load", suffix: "mm/tooth") {
                TextField("", value: $chipLoad,
                          format: .number.precision(.fractionLength(0...4)).locale(Locale(identifier: "en_US")))
            }
            row("Flutes", suffix: "") {
                TextField("", value: $flutes, format: .number.grouping(.never))
            }
            row("Spindle", suffix: "rpm") {
                TextField("", value: $rpm, format: .number.grouping(.never))
            }
            if usesStepover {
                row("Stepover", suffix: "%") {
                    TextField("", value: $stepOver,
                              format: .number.precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US")))
                }
            }

            if !toolHasFlutes && flutes == 0 {
                InspectorNote(text: "The tool has no flutes set: enter them here.")
            }

            Divider()

            HStack {
                Text("Feed")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("\(Int(feed)) mm/min")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                Spacer()
                Button("Use value") {
                    onUse(feed)
                }
                .disabled(!canUse)
            }

            if feed > 0 {
                InspectorNote(text: "Current feed: \(currentFeed.roundedInt) mm/min", isIndented: false)
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    // MARK: The cut

    /// The glyph of the direction picker at this chip load and stepover, with what it means
    /// under it: the color is the heat, the numbers are what the cut takes off.
    @ViewBuilder
    private func cutDrawing(_ analysis: ChipLoadAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            DirectionGlyph(direction: direction,
                           tint: .secondary,
                           feedPerTooth: glyphFeedPerTooth,
                           stepOverFraction: CGFloat(analysis.engagement),
                           chipTint: analysis.tint,
                           heat: analysis.heat)
                .frame(width: 150, height: 100)
                .frame(maxWidth: .infinity)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .animation(.easeOut(duration: 0.15), value: analysis.heat)

            if analysis.isComplete {
                heatBar(analysis)

                HStack(spacing: 10) {
                    stat("Chip", "\(ChipLoadAnalysis.format(analysis.chipThickness)) mm")
                    stat("Removal", "\(Self.format(analysis.removalRate)) cm³/min")
                    stat("Speed", "\(analysis.surfaceSpeed.roundedInt) m/min")
                }
            }

            Text(analysis.message)
                .font(.system(size: 11))
                .foregroundStyle(analysis.verdict == .good || analysis.verdict == .incomplete
                                 ? Color.secondary : analysis.tint)
                .fixedSize(horizontal: false, vertical: true)

            if let note = analysis.thinningNote {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The chip load in the glyph's design units (the tool is 24 wide there). A real chip is a
    /// hair next to the tool, so every value is drawn 40 times larger, which keeps the
    /// differences between values visible without losing the proportions.
    private var glyphFeedPerTooth: CGFloat {
        guard toolDiameter > 0, chipLoad > 0 else {
            return 0.8
        }
        return min(max(CGFloat(chipLoad / toolDiameter) * 24 * 40, 0.8), 9)
    }

    /// A thin green-to-red bar with a marker where this cut is.
    private func heatBar(_ analysis: ChipLoadAnalysis) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: [HeatColor.color(for: 0), HeatColor.color(for: 0.5), HeatColor.color(for: 1)],
                                         startPoint: .leading, endPoint: .trailing))
                    .opacity(0.55)
                    .frame(height: 4)
                Circle()
                    .fill(analysis.tint)
                    .overlay(Circle().stroke(Color.primary.opacity(0.5), lineWidth: 1))
                    .frame(width: 9, height: 9)
                    .offset(x: (geo.size.width - 9) * CGFloat(analysis.heat))
                    .animation(.easeOut(duration: 0.15), value: analysis.heat)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 10)
        .help("How hot the cut runs: green while the chip carries the heat away, red when the tool is rubbing")
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US")))
    }

    private func row<Field: View>(_ title: String, suffix: String,
                                  @ViewBuilder field: () -> Field) -> some View {
        InspectorRow(label: title, labelWidth: 70) {
            HStack(spacing: 6) {
                field()
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .multilineTextAlignment(.leading)
                if !suffix.isEmpty {
                    Text(suffix)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            .inspectorField()
        }
    }
}

#Preview {
    DirectionGlyph(direction: .climb, tint: .secondary, feedPerTooth: 4, stepOverFraction: 0.4,
                   chipTint: HeatColor.color(for: 0.8), heat: 0.8)
        .frame(width: 150, height: 100)
        .padding()
}
