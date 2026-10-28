//
//  ToolpathDetailsModel.swift
//  Stratum CNC
//
//  Logic behind `PanelToolpathDetails`: bindings that translate between what the fields
//  show and what is stored, tool presets, the preview slider and the status texts.
//

import SwiftUI
import StratumCAM

final class ToolpathDetailsModel: ObservableObject {

    /// What the last tool pick did to the cutting values, shown under the tool.
    @Published var presetNote: String?

    /// Where the preview slider is; nil = at the end (the whole toolpath), which is where a
    /// new result starts. Kept here rather than in the toolpath model so a drag only redraws
    /// the panel.
    @Published var scrubStep: Int?

    /// Forgets per-toolpath UI state, when another toolpath is opened.
    func reset() {
        presetNote = nil
        scrubStep = nil
    }

    /// A new Generate starts its preview from the end again, like the canvas does.
    func resetScrub() {
        scrubStep = nil
    }

    // MARK: Header / operation

    /// Typing a name is what makes it "custom" -- from then on it stops following the
    /// operation (see `operationKindBinding`).
    func nameBinding(_ toolpath: Binding<ToolpathData>) -> Binding<String> {
        Binding(
            get: { toolpath.wrappedValue.name },
            set: {
                toolpath.wrappedValue.name = $0
                toolpath.wrappedValue.isNameCustom = true
            }
        )
    }

    /// Changing the operation also renames the toolpath to match -- "Contour 1",
    /// "Pocket 1", ... -- but only while the name is still the auto-generated one;
    /// once the user has typed their own title it stops following the operation.
    func operationKindBinding(_ toolpath: Binding<ToolpathData>,
                              siblingNames: Set<String>) -> Binding<OperationKind> {
        Binding(
            get: { toolpath.wrappedValue.operation.kind },
            set: { newKind in
                toolpath.wrappedValue.operation.kind = newKind
                // Untouched fields take the new operation's defaults; edited ones stay.
                toolpath.wrappedValue.applyDefaults(for: newKind)
                if !toolpath.wrappedValue.isNameCustom {
                    toolpath.wrappedValue.name = newKind.nextName(among: siblingNames)
                }
            }
        )
    }

    /// Which of the general fields (End Z, Stepdown, Stepover) the operation reads, as the
    /// library defines it for the operation's current values.
    func requirements(for toolpath: ToolpathData) -> SC.OperationRequirements {
        toolpath.machiningOperation.requirements
    }

    // MARK: Tool

    /// Fills spindle speed, feeds, stepdown and ramp angle from the picked tool's
    /// preset for the current stock. Only runs on an explicit pick, so opening a
    /// toolpath never overwrites its values.
    func applyPreset(of tool: Tool, to toolpath: Binding<ToolpathData>, stockMaterial: StockMaterialType) {
        if let preset = tool.preset(for: stockMaterial) {
            toolpath.wrappedValue.apply(preset)
            presetNote = "Applied the \"\(preset.name)\" preset"
        } else if tool.presets.isEmpty {
            presetNote = "This tool has no presets; values unchanged"
        } else {
            presetNote = "No preset for \(stockMaterial.displayName); values unchanged"
        }
    }

    func plungeFeedHelp(for toolpath: ToolpathData) -> String {
        toolpath.ramping.enabled && toolpath.ramping.type != .none
            ? "Feed rate going down into the material, also along the ramp or helix entry."
            : "Feed rate going down into the material."
    }

    // MARK: Z levels

    /// A binding that also records the field as edited when the user changes its value,
    /// so changing the operation later leaves it alone.
    func editedBinding(_ value: Binding<Double>,
                       _ field: ToolpathField,
                       in toolpath: Binding<ToolpathData>) -> Binding<Double> {
        Binding(
            get: { value.wrappedValue },
            set: { newValue in
                guard newValue != value.wrappedValue else {
                    return
                }
                value.wrappedValue = newValue
                toolpath.wrappedValue.markEdited(field)
            }
        )
    }

    /// End Z is typed as a positive depth below the top (the "−" is shown in front of the
    /// field), but stored and sent on as the negative Z value. A minus typed anyway is ignored.
    func endDepth(_ toolpath: Binding<ToolpathData>) -> Binding<Double> {
        Binding(
            get: { -toolpath.wrappedValue.endZ },
            set: { toolpath.wrappedValue.endZ = -abs($0) }
        )
    }

    /// A counterbore's depth, shown as its End Z: typed as a positive depth below the top with
    /// the "−" in front, like every other operation's End Z. It is stored as the positive
    /// `counterboreDepth` the library takes, so nothing about saved projects changes.
    func counterboreEndDepth(_ toolpath: Binding<ToolpathData>) -> Binding<Double> {
        Binding(
            get: { toolpath.wrappedValue.operation.counterboreDepth },
            set: { toolpath.wrappedValue.operation.counterboreDepth = ToolpathData.clampedCounterboreDepth(abs($0)) }
        )
    }

    func slotDepthPerPass(_ toolpath: Binding<ToolpathData>) -> Binding<Double> {
        Binding(
            get: { toolpath.wrappedValue.operation.slotDepthPerPass },
            set: { toolpath.wrappedValue.operation.slotDepthPerPass = ToolpathData.clampedDepthPerPass(abs($0)) }
        )
    }

    func drillPeckDepth(_ toolpath: Binding<ToolpathData>) -> Binding<Double> {
        Binding(
            get: { toolpath.wrappedValue.operation.drillPeckDepth },
            set: { toolpath.wrappedValue.operation.drillPeckDepth = ToolpathData.clampedDepthPerPass(abs($0)) }
        )
    }

    /// Drill, bore and thread mill make holes, which usually go all the way through.
    func isHoleOperation(_ toolpath: ToolpathData) -> Bool {
        switch toolpath.operation.kind {
            case .drilling, .boring, .threadMilling:
                return true
            default:
                return false
        }
    }

    /// The Z the "Through stock" helper sets: the underside of the stock.
    func throughStockZ(thickness: Double) -> Double {
        -thickness
    }

    func isThroughStock(_ toolpath: ToolpathData, thickness: Double) -> Bool {
        abs(toolpath.endZ - throughStockZ(thickness: thickness)) < 1e-6
    }

    /// Sets End Z to the bottom of the stock. The tip stops exactly at the underside, so
    /// add a little extra by hand if the hole must clear the spoilboard.
    func applyThroughStock(to toolpath: Binding<ToolpathData>, thickness: Double) {
        toolpath.wrappedValue.endZ = throughStockZ(thickness: thickness)
        toolpath.wrappedValue.markEdited(.endZ)
    }

    func throughStockHelp(thickness: Double) -> String {
        let format = FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(0...2))
            .locale(Locale(identifier: "en_US"))
        return "Set End Z to the bottom of the stock (\(throughStockZ(thickness: thickness).formatted(format)) mm)"
    }

    // MARK: Preview

    func previewButtonHelp(for toolpath: ToolpathData) -> String {
        toolpath.leadInConflictsWithEntry
            ? "A lead-in can't be combined with a ramp or helix entry. Turn the entry off or remove the lead-in."
            : "Build the toolpath for the selected shapes and preview it on the canvas"
    }

    /// The slider's position as a binding over the step count; moving it reports the new
    /// step through `onScrub`.
    func scrubBinding(total: Int, onScrub: @escaping (Int) -> Void) -> Binding<Double> {
        Binding(
            get: { [weak self] in
                Double(self?.scrubStep ?? total)
            },
            set: { [weak self] newValue in
                guard let self else {
                    return
                }
                let step = Int(newValue.rounded())
                guard step != (self.scrubStep ?? total) else {
                    return
                }
                self.scrubStep = step
                onScrub(step)
            }
        )
    }

    func scrubLabel(total: Int) -> String {
        "\(scrubStep ?? total) / \(total)"
    }

    func successText(for generation: ToolpathGeneration) -> String {
        let toolpaths = generation.outputCount
        let passes = generation.passCount
        return "\(toolpaths) toolpath\(toolpaths == 1 ? "" : "s") · \(passes) pass\(passes == 1 ? "" : "es")"
    }

    func multiPassNote(for generation: ToolpathGeneration) -> String {
        "The preview shows only the last pass. The G-code cuts all \(generation.maxPassesPerToolpath) passes."
    }

    // MARK: Shapes

    func shapesTitle(for toolpath: ToolpathData) -> String {
        if toolpath.cutsWholeStock {
            let ignored = toolpath.targets.count
            return ignored == 0
                ? "Whole stock"
                : "Whole stock (\(ignored) selected shape\(ignored == 1 ? "" : "s") ignored)"
        }
        switch toolpath.targets.count {
            case 0: return "Click shapes to select"
            case 1: return "1 shape selected"
            default: return "\(toolpath.targets.count) shapes selected"
        }
    }
}
