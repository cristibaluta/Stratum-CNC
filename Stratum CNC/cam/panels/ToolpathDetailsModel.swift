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
        replacedName = nil
    }

    /// A new Generate starts its preview from the end again, like the canvas does.
    func resetScrub() {
        scrubStep = nil
    }

    // MARK: Header / operation

    /// The name the last operation change replaced, for this open toolpath only. A title
    /// field that was still being edited shows that old text and writes it back when it ends
    /// editing, which would undo the rename.
    private var replacedName: String?

    /// What is typed in the title is written as it is. The name is only touched again when
    /// the operation changes (see `operationKindBinding`); nothing is flagged or saved.
    func nameBinding(_ toolpath: Binding<ToolpathData>) -> Binding<String> {
        Binding(
            get: { toolpath.wrappedValue.name },
            set: { [weak self] newValue in
                // A TextField can write its binding on focus/commit with unchanged text.
                guard newValue != toolpath.wrappedValue.name else {
                    return
                }
                // The stale text of a field that missed the automatic rename.
                if newValue == self?.replacedName {
                    return
                }
                self?.replacedName = nil
                toolpath.wrappedValue.name = newValue
            }
        )
    }

    /// Changing the operation always renames the toolpath to match -- "Contour 1" ->
    /// "Pocket 1" -- whatever its name was. Editing the name never triggers this, only
    /// picking an operation does.
    func operationKindBinding(_ toolpath: Binding<ToolpathData>,
                              siblingNames: Set<String>) -> Binding<OperationKind> {
        Binding(
            get: { toolpath.wrappedValue.operation.kind },
            set: { [weak self] newKind in
                toolpath.wrappedValue.operation.kind = newKind
                // Untouched fields take the new operation's defaults; edited ones stay.
                toolpath.wrappedValue.applyDefaults(for: newKind)
                let oldName = toolpath.wrappedValue.name
                let newName = newKind.nextName(among: siblingNames)
                if newName != oldName {
                    self?.replacedName = oldName
                    toolpath.wrappedValue.name = newName
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

    // MARK: Z axis

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

    /// Tooltip of the End Z field.
    let endZHelp = "The depth the cut reaches, measured from the probed Z0, not from Start Z. Only depths below Z0 are supported: type it as a positive number and it is applied as a negative Z value."

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

    /// Drill, bore and thread mill make holes, which usually go all the way through; so does a
    /// contour, which cuts the part free of the stock.
    func offersThroughStock(_ toolpath: ToolpathData) -> Bool {
        switch toolpath.operation.kind {
            case .drilling, .boring, .threadMilling, .contour:
                return true
            default:
                return false
        }
    }

    /// How far below the underside of the stock a contour goes, mm, so the part comes free
    /// even when Z0 is a few hundredths off. Holes stop exactly at the underside.
    static let contourOvercut: Double = 0.2

    /// The overcut `applyThroughStock` adds for this operation.
    func overcut(for toolpath: ToolpathData) -> Double {
        toolpath.operation.kind == .contour ? Self.contourOvercut : 0
    }

    /// The Z the "Through stock" helper sets: the underside of the stock, plus the overcut.
    func throughStockZ(for toolpath: ToolpathData, thickness: Double) -> Double {
        -(thickness + overcut(for: toolpath))
    }

    func isThroughStock(_ toolpath: ToolpathData, thickness: Double) -> Bool {
        abs(toolpath.endZ - throughStockZ(for: toolpath, thickness: thickness)) < 1e-6
    }

    /// Sets End Z to the bottom of the stock (a contour a little below it, see `overcut`). A hole's
    /// tip stops exactly at the underside, so add a little extra by hand if it must clear the spoilboard.
    func applyThroughStock(to toolpath: Binding<ToolpathData>, thickness: Double) {
        toolpath.wrappedValue.endZ = throughStockZ(for: toolpath.wrappedValue, thickness: thickness)
        toolpath.wrappedValue.markEdited(.endZ)
    }

    func throughStockHelp(for toolpath: ToolpathData, thickness: Double) -> String {
        let format = FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(0...2))
            .locale(Locale(identifier: "en_US"))
        let z = throughStockZ(for: toolpath, thickness: thickness).formatted(format)
        let extra = overcut(for: toolpath)
        guard extra > 0 else {
            return "Set End Z to the bottom of the stock (\(z) mm)"
        }
        return "Set End Z to the bottom of the stock plus a \(extra.formatted(format)) mm overcut (\(z) mm), so the part comes free. Needs a spoilboard under the stock."
    }

    // MARK: Passes

    /// A caption under Stepdown (or a slot's Depth per pass) saying how many passes the
    /// Z range comes to, so a wrong stepdown or End Z shows at a glance.
    struct PassesNote {
        let text: String
        let isWarning: Bool
    }

    /// The passes from the top of the cut down to End Z in steps of `stepdown`, the last one
    /// shorter when the depth isn't a multiple of it. The top of the cut is Start Z, or Z0 when
    /// Start Z is above it (the library starts at the top of the stock, see
    /// `ToolpathGenerator.droppingPasses`). A counterbore cuts down to its own depth, not End Z.
    /// `nil` when the stepdown isn't usable (the field's own clamp deals with it).
    func passesNote(for toolpath: ToolpathData, stepdown: Double) -> PassesNote? {
        guard stepdown > 0 else {
            return nil
        }
        let top = min(toolpath.startZ, 0)
        let bottom = toolpath.operation.kind == .counterbore
            ? -toolpath.operation.counterboreDepth
            : toolpath.endZ
        let depth = top - bottom
        guard depth > 1e-9 else {
            return PassesNote(text: "End Z is not below Start Z: nothing to cut.", isWarning: true)
        }

        // The small offset keeps 1.1 / 0.1 (= 11.000000000000002) at 11 passes instead of 12.
        let count = max(1, Int((depth / stepdown - 1e-9).rounded(.up)))
        let format = FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(0...2))
            .locale(Locale(identifier: "en_US"))
        var text = "\(count) pass\(count == 1 ? "" : "es") to Z \u{2212}\(abs(bottom).formatted(format))"

        let last = depth - Double(count - 1) * stepdown
        if count > 1, abs(last - stepdown) > 1e-6 {
            text += " (last one \(last.formatted(format)) mm)"
        }
        return PassesNote(text: text, isWarning: false)
    }

    // MARK: Preview

    func previewButtonHelp(for toolpath: ToolpathData) -> String {
        if !toolpath.hasGeometry {
            return "Click shapes on the canvas first: there is nothing to preview yet."
        }
        return "Build the toolpath for the selected shapes and preview it on the canvas"
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
