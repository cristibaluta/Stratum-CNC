//
//  OperationOptionsView.swift
//  Stratum CNC
//
//  The controls that change with the chosen operation: a contour has a side, a drill has an
//  optional peck depth, a counterbore has a diameter and a depth… They are placed by what they
//  do: what the operation is (under the operation picker), in the plane (XY plane), down into
//  the material (Z axis) or how the tool gets into the cut (Entry).
//

import SwiftUI
import StratumCAM

struct OperationOptionsView: View {

    @Binding var toolpath: ToolpathData

    /// The selected shapes' outlines (see `PanelToolpathDetails.targetShapes`), for the holding
    /// tabs drawing.
    var targetShapes: () -> [CGPath] = { [] }

    @State private var showRampEditor = false
    @State private var showTabsEditor = false
    @State private var showLeadInEditor = false
    @State private var showLeadOutEditor = false

    private var kind: OperationKind {
        toolpath.operation.kind
    }

    /// What the library says the operation takes and accepts; every optional row below is
    /// shown because of it, not because of the operation's kind.
    private var requirements: SC.OperationRequirements {
        toolpath.machiningOperation.requirements
    }

    /// The patterns to offer in the pattern row: the pocket's. A slot has patterns of its own
    /// (`requirements.slotPatterns`), which the app doesn't offer until open-ended slots can
    /// be derived from the drawing.
    private var offeredPatterns: [PocketPattern] {
        requirements.pocketPatterns.map { PocketPattern($0) }
    }

    /// Which section of the panel this instance fills. The panel places one of each, so the
    /// operation's controls are grouped by what they do instead of sitting in one list.
    enum Part {
        /// What the selection is, where the operation needs to know (a slot: its outline or the
        /// line the tool centre follows). Shown in "Shapes".
        case shapes
        /// What the operation is, shown in the header under the operation picker: the side of a
        /// contour or chamfer, a pocket's clearing pattern, and the library's fields that are
        /// neither a direction nor a depth (a thread's standard, pitch and diameter, the diameter
        /// of a bore or a counterbore, a chamfer's width, a facing's extension).
        case operation
        /// How the tool moves in the plane: cut direction, feed rate, stepover, stock to leave.
        case xyMovement
        /// The operation's own depth settings (dwell, shift before retract, a chamfer's depth
        /// override). Shown in "Z axis".
        case depth
        /// How the tool descends into the material (ramp / helix / plunge). Shown in "Entry".
        case entry
        /// A contour's lead-in and lead-out, with the note when the lead-in clashes with the entry.
        /// Shown in "Entry".
        case leadInOut
        /// The holding tabs of a contour, which leave material standing at the bottom. Shown in "Z axis".
        case tabs
    }

    var part: Part = .xyMovement

    /// The cut direction (climb / conventional) fields `formFields` builds. They are shown in
    /// the XY plane section next to the other movement settings.
    private static let xyDirectionFieldIDs: Set<String> = [
        "facing.direction", "contour.direction", "pocket.direction",
        "counterbore.direction", "chamfer.params.direction"
    ]

    /// The library's fields that are about the depth: the bottom of a bore and its retract, how
    /// deep a chamfer goes. They are shown in the Z axis section, the rest in the operation's own.
    private static let zFieldIDs: Set<String> = [
        "boring.dwellTime", "boring.shiftRetract", "chamfer.params.depth"
    ]

    /// Whether the "Z axis" section has fields of the operation's own (see `zFieldIDs`).
    static func hasDepthFields(for toolpath: ToolpathData) -> Bool {
        toolpath.operation.kind == .boring || toolpath.operation.kind == .chamfer
    }

    /// Whether the "Z axis" section has a holding tabs row for this toolpath.
    static func hasTabs(for toolpath: ToolpathData) -> Bool {
        toolpath.operation.kind == .contour
    }

    /// Whether the "Entry" section has a lead-in and lead-out for this toolpath.
    static func hasLeadInOut(for toolpath: ToolpathData) -> Bool {
        toolpath.operation.kind == .contour
    }

    /// Whether the "Entry" section has an entry row for this toolpath.
    static func hasEntry(for toolpath: ToolpathData) -> Bool {
        toolpath.machiningOperation.requirements.usesEntry
    }

    /// The library's own fields of the operation, as the "operation" section shows them: not
    /// a direction or a depth (those sit in the XY plane and Z axis sections) and not something
    /// the app draws with a control of its own.
    private static func operationFields(of toolpath: ToolpathData) -> [SC.ParameterField] {
        let kind = toolpath.operation.kind
        let fields = displayedFields(of: toolpath.machiningOperation.formFields(onChange: { _ in }), kind: kind)
        let hiddenIDs = hiddenOperationFieldIDs(for: kind)
        return fields.filter { !hiddenIDs.contains($0.id) }
    }

    /// Field ids that belong to another section (direction, depth) or to a control of the app's own.
    private static func hiddenOperationFieldIDs(for kind: OperationKind) -> Set<String> {
        kind.hiddenFieldIDs.union(xyDirectionFieldIDs).union(zFieldIDs)
    }

    /// Whether the operation has settings of its own to show under its type.
    static func hasOperationFields(for toolpath: ToolpathData) -> Bool {
        switch toolpath.operation.kind {
            case .contour, .chamfer:
                return true   // the side
            default:
                break
        }
        return !toolpath.machiningOperation.requirements.pocketPatterns.isEmpty
            || !operationFields(of: toolpath).isEmpty
    }

    var body: some View {
        switch part {
            case .shapes: shapesPart
            case .operation: operationPart
            case .xyMovement: xyMovementPart
            case .depth: depthPart
            case .entry: entryPart
            case .leadInOut: leadInOutPart
            case .tabs: tabsPart
        }
    }

    // MARK: Form

    private var formFields: [SC.ParameterField] {
        toolpath.machiningOperation.formFields(
            threadIsCustom: toolpath.operation.threadIsCustom,
            onThreadCustomChange: { toolpath.operation.threadIsCustom = $0 },
            onChange: { toolpath.machiningOperation = $0 }
        )
    }

    // MARK: Shapes

    /// A slot's selection is either its outline or the line the tool centre follows.
    private var shapesPart: some View {
        VStack(alignment: .leading, spacing: Inspector.rowSpacing) {
            if kind == .slotting {
                EnumMenuPicker(title: "Selection is", selection: $toolpath.operation.slotSource)
                // The engine only accepts an outline exactly as wide as the tool; say so here
                // instead of at Preview (see `ToolpathGenerator.run`).
                if toolpath.operation.slotSource == .outline {
                    InspectorNote(text: slotOutlineNote)
                }
            }
        }
    }

    // MARK: Operation

    /// What the library defines for the operation besides the direction and the depths:
    /// a chamfer's width, the diameter of a counterbore or a bore, a thread, a facing's extension.
    private var operationPart: some View {
        let hiddenIDs = Self.hiddenOperationFieldIDs(for: kind)
        let fields = displayedFields(of: formFields).filter { !hiddenIDs.contains($0.id) }

        return VStack(alignment: .leading, spacing: Inspector.rowSpacing) {
            // Which side of the boundary the tool follows -- same glyph-based picker
            // for both, since `ContourPicker` is generic over `CutSideOption`.
            if kind == .contour {
                ContourPicker(selection: $toolpath.contour, title: "Side")
            } else if kind == .chamfer {
                ContourPicker(selection: $toolpath.operation.chamferSide)
            }

            if !fields.isEmpty {
                ParameterFieldsView(fields: fields,
                                    hiddenFieldIDs: hiddenIDs,
                                    hiddenCaseIDs: OperationKind.hiddenCaseIDs)
            }

            // The clearing pattern keeps its own dedicated picker (icon glyphs, same as
            // `ContourTypeGlyph`), followed by its one extra control: it shapes how the area is cleared.
            if !offeredPatterns.isEmpty {
                PatternPicker(pattern: $toolpath.operation.pocketPattern, available: offeredPatterns)
                patternDetail
            }
        }
    }

    // MARK: XY plane

    private var xyMovementPart: some View {
        let fields = displayedFields(of: formFields)

        return VStack(alignment: .leading, spacing: Inspector.rowSpacing) {
            // Climb / conventional: how the tool travels along the path
            let directionFields = fields.filter { Self.xyDirectionFieldIDs.contains($0.id) }
            if !directionFields.isEmpty {
                ParameterFieldsView(fields: directionFields)
            }

            // Feed rate of the cutting moves in the plane (the entry's own feed is in the Entry section)
            InspectorNumberField(title: "Feed rate", value: $toolpath.feedRate, suffix: "mm/min")

            // Stepover is about how the area is cleared (facing included).
            if usesStepover {
                stepOverRow
            }

            // Stock for a finishing pass: wherever the library says the operation can leave some.
            if requirements.usesAllowance {
                stockToLeaveRows
            }
        }
    }

    // MARK: Lead-in / lead-out (shown in the Entry section)

    private var leadInOutPart: some View {
        VStack(alignment: .leading, spacing: Inspector.rowSpacing) {
            // The library refuses a lead-in together with a ramp or helix entry; say so here
            // (Preview is held back too, see `PanelToolpathDetails`) instead of failing there.
            if toolpath.leadInConflictsWithEntry {
                leadInConflictNote
            }

            // Lead-in / lead-out: a switch with a summary of what it is set to, and a gear that
            // opens the editor (with a drawing of the move) in a popover.
            if kind == .contour {
                leadInOutRow(title: "Lead-In",
                             role: .leadIn,
                             binding: $toolpath.operation.contourLeadIn,
                             isPresented: $showLeadInEditor,
                             needsAttention: toolpath.leadInConflictsWithEntry)
                leadInOutRow(title: "Lead-Out",
                             role: .leadOut,
                             binding: $toolpath.operation.contourLeadOut,
                             isPresented: $showLeadOutEditor)
            }
        }
    }

    // MARK: Depth (shown in the Z axis section)

    private var depthPart: some View {
        let depthFields = displayedFields(of: formFields).filter { Self.zFieldIDs.contains($0.id) }

        return VStack(alignment: .leading, spacing: Inspector.rowSpacing) {
            if !depthFields.isEmpty {
                ParameterFieldsView(fields: depthFields)
            }
            if kind == .chamfer {
                chamferDepthNote
            }
        }
    }

    // MARK: Holding tabs (shown in the Z axis section)

    /// A summary row that opens the editor in a popover.
    @ViewBuilder
    private var tabsPart: some View {
        if Self.hasTabs(for: toolpath) {
            HoldingTabsButton(tabs: toolpath.operation.contourTabs) {
                showTabsEditor = true
            }
            .popover(isPresented: $showTabsEditor, attachmentAnchor: .rect(.bounds), arrowEdge: .leading) {
                HoldingTabsEditor(tabs: $toolpath.operation.contourTabs, shapes: targetShapes)
                    .frame(width: 400)
            }
        }
    }

    // MARK: Entry (shown in the Entry section)

    private var entryPart: some View {
        // The entry strategy keeps its dedicated editor (angle/length preview, helix
        // diagram), but whether an operation has one is up to the library.
        VStack(alignment: .leading, spacing: Inspector.rowSpacing) {
            if requirements.usesEntry {
                rampingRow
            }
        }
        // The ramping settings are shared by every operation, so one left over from another
        // operation (a helix, say) may be one this operation can't use.
        .onAppear { normalizeRampType() }
        .onChange(of: kind) { _, _ in normalizeRampType() }
    }

    /// The form's fields as the panel shows them. A chamfer's parameters come in a group titled
    /// "Chamfer", which only repeats the operation's own name, so they are shown directly (with
    /// the side picker first, above them).
    private func displayedFields(of fields: [SC.ParameterField]) -> [SC.ParameterField] {
        Self.displayedFields(of: fields, kind: kind)
    }

    private static func displayedFields(of fields: [SC.ParameterField], kind: OperationKind) -> [SC.ParameterField] {
        guard kind == .chamfer else {
            return fields
        }
        return fields.flatMap { field -> [SC.ParameterField] in
            if case .group(let group) = field, group.id == "chamfer.params" {
                return group.fields
            }
            return [field]
        }
    }

    /// How deep the chamfer goes: the fixed depth, or what the V-bit's angle gives for the width.
    /// A tool without a tip angle is flagged under the tool instead (`toolCompatibilityWarning`).
    @ViewBuilder
    private var chamferDepthNote: some View {
        if let depth = toolpath.chamferResolvedDepth {
            if toolpath.operation.chamferUsesDepth {
                InspectorNote(text: String(format: "Depth = %.2f mm (fixed).", depth))
            } else if let angle = toolpath.toolTipAngle {
                InspectorNote(text: String(format: "Depth = %.2f mm for a %.0f° bit.", depth, angle))
            }
        }
    }

    private var slotOutlineNote: String {
        let diameter = Double(toolpath.tool.toolDiameter)
        guard diameter > 0 else {
            return "The outline must be a straight-sided rectangle as wide as the tool. Pick a tool to see the width."
        }
        return String(format: "The outline must be a straight-sided rectangle exactly Ø%.2f mm wide, the tool's diameter.", diameter)
    }

    private func leadInOutRow(title: String,
                              role: LeadInOutEditor.Role,
                              binding: Binding<LeadInOutSettings?>,
                              isPresented: Binding<Bool>,
                              needsAttention: Bool = false) -> some View {
        LeadInOutRow(title: title, leadInOut: binding, needsAttention: needsAttention) {
            isPresented.wrappedValue = true
        }
        .popover(isPresented: isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .leading) {
            LeadInOutEditor(role: role,
                            leadInOut: binding,
                            side: toolpath.contour,
                            toolDiameter: Double(toolpath.tool.toolDiameter))
                .frame(width: 400)
        }
    }

    private var leadInConflictNote: some View {
        HStack(alignment: .top, spacing: Inspector.columnSpacing) {
            Color.clear
                .frame(width: Inspector.labelWidth, height: 0)
            VStack(alignment: .leading, spacing: 6) {
                Label("A lead-in can't be combined with a ramp or helix entry: the entry already eases the tool in. Turn the entry off or remove the lead-in.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Turn entry off") {
                    toolpath.ramping.enabled = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Stepover, typed as a percentage of the tool diameter; what that comes to in mm is
    /// spelled out underneath, since that's what the machine actually steps.
    /// The only clamp is `ToolpathData.stepOverRange`.
    @ViewBuilder
    private var stepOverRow: some View {
        InspectorNumberField(title: "Stepover", value: stepOverPercent, suffix: "% of Ø")
        InspectorNote(text: stepOverNote)
    }

    /// Whether the stepover row is shown: whatever the library says reads it (facing included).
    private var usesStepover: Bool {
        requirements.usesStepover
    }

    private var stepOverPercent: Binding<Double> {
        Binding(
            get: { toolpath.stepOverPercent },
            set: { newValue in
                let clamped = ToolpathData.clampedStepOver(newValue)
                guard clamped != toolpath.stepOverPercent else {
                    return
                }
                toolpath.stepOverPercent = clamped
                toolpath.markEdited(.stepOver)
            }
        )
    }

    private var stepOverNote: String {
        let diameter = Double(toolpath.tool.toolDiameter)
        guard diameter > 0 else {
            return "Pick a tool to see the stepover in mm."
        }
        return String(format: "= %.2f mm for a Ø%.2f mm tool", toolpath.stepOverMM, diameter)
    }

    /// Stock to leave and the finishing pass. The roughing stays `stockToLeave` away from the
    /// walls (and from a pocket's floor); the finishing pass, when on, cuts that stock away.
    /// The only clamp is `ToolpathData.stockToLeaveRange`.
    @ViewBuilder
    private var stockToLeaveRows: some View {
        InspectorNumberField(title: "Stock to leave", value: stockToLeave, suffix: "mm")
            .help(kind == .pocket
                  ? "Material left standing on the walls and the floor by the roughing. 0 cuts straight to size."
                  : "Material left standing on the wall by the roughing. 0 cuts straight to size.")
        if toolpath.operation.stockToLeave > 0 {
            ToggleField(title: "Finishing pass",
                        isOn: $toolpath.operation.finishingPass,
                        help: kind == .pocket
                            ? "After the roughing, cuts the floor and then the walls to size. Uses the same stepdown."
                            : "After the roughing, cuts the contour again at its true size, with the same entry, lead-in/out and tabs. Uses the same stepdown.")
            InspectorNote(text: stockToLeaveNote, isWarning: toolpath.stockToLeaveExceedsDepth)
        }
    }

    private var stockToLeave: Binding<Double> {
        Binding(
            get: { toolpath.operation.stockToLeave },
            set: { toolpath.operation.stockToLeave = ToolpathData.clampedStockToLeave($0) }
        )
    }

    private var stockToLeaveNote: String {
        let stock = toolpath.operation.stockToLeave
        if toolpath.stockToLeaveExceedsDepth {
            return String(format: "The stock to leave must be less than the depth (%.2f mm): the floor is left too.", abs(toolpath.endZ))
        }
        let amount = String(format: "%.2f", stock)
        let place = kind == .pocket ? "the walls and the floor" : "the wall"
        if toolpath.operation.finishingPass {
            return "Roughing leaves \(amount) mm on \(place); the finishing pass cuts it to size."
        }
        return "Leaves \(amount) mm on \(place). Turn on Finishing pass to cut it, or finish it with another toolpath."
    }

    /// The ramp types the operation accepts, taken from the entry strategies the library
    /// offers for it (an engraving has no helix, for instance).
    private var availableRampTypes: [RampType] {
        var types: [RampType] = []
        for entry in requirements.entries {
            switch entry {
                case .plunge:      types.append(.none)
                case .ramp:        types.append(.linear)
                case .helix:       types.append(.helix)
                case .fromOpenEnd: break   // not offered by the app, see `OperationKind.hiddenCaseIDs`
            }
        }
        return types
    }

    /// Switches a ramp type the operation doesn't accept to the closest one it does: a
    /// helix becomes a linear ramp at the same angle.
    private func normalizeRampType() {
        let available = availableRampTypes
        guard requirements.usesEntry,
              !available.isEmpty,
              !available.contains(toolpath.ramping.type) else {
            return
        }
        toolpath.ramping.type = available.contains(.linear) ? .linear : .none
    }

    /// Ramping gets its own rows, since it applies across very different operations.
    /// Once a method (anything other than "None") is chosen, its angle sits right
    /// below the button -- bound to the same `toolpath.ramping.angle` the popover
    /// edits, so the two always agree.
    @ViewBuilder
    private var rampingRow: some View {
        rampingButton
        if toolpath.ramping.type != .none {
            InspectorNumberField(title: "Entry angle", value: $toolpath.ramping.angle, suffix: "°")
        }
    }

    private var rampingButton: some View {
        RampingButton(ramping: $toolpath.ramping, available: availableRampTypes) {
            showRampEditor = true
        }
        .popover(isPresented: $showRampEditor, attachmentAnchor: .rect(.bounds), arrowEdge: .leading) {
            // A slot steps down by its own depth-per-pass, not by the general stepdown.
            RampingEditor(ramping: $toolpath.ramping,
                          feedRate: $toolpath.plungeRate,
                          stepdown: kind == .slotting ? toolpath.operation.slotDepthPerPass : toolpath.stepDown,
                          toolDiameter: Double(toolpath.tool.toolDiameter),
                          available: availableRampTypes)
                .frame(width: 400)
        }
    }

    /// Clamped to what the library accepts, like the stepover, instead of failing at Preview.
    private var trochoidalPitch: Binding<Double> {
        Binding(
            get: { toolpath.operation.pocketTrochoidalPitch },
            set: { toolpath.operation.pocketTrochoidalPitch = ToolpathData.clampedTrochoidalPitch($0) }
        )
    }

    private var adaptiveLoad: Binding<Double> {
        Binding(
            get: { toolpath.operation.pocketAdaptiveLoadPercent },
            set: { toolpath.operation.pocketAdaptiveLoadPercent = ToolpathData.clampedAdaptiveLoad($0) }
        )
    }

    private var adaptiveLoadNote: String {
        let diameter = Double(toolpath.tool.toolDiameter)
        guard diameter > 0 else {
            return "Pick a tool to see the load in mm."
        }
        return String(format: "= %.2f mm radial engagement (tool Ø%.2f mm)", toolpath.adaptiveLoadMM, diameter)
    }

    /// The one extra control a pattern needs, if any -- which way a spiral winds in,
    /// how tightly a trochoidal loop steps forward, or how much of the tool an adaptive
    /// pass is allowed to bury in the material. These are only stored on
    /// `OperationSettings`, not exposed by the generic form once `pattern` is hidden.
    @ViewBuilder
    private var patternDetail: some View {
        switch toolpath.operation.pocketPattern {
            case .spiral, .concentric:
                EnumMenuPicker(title: "Spiral direction", selection: $toolpath.operation.pocketSpiral)
            case .trochoidal:
                InspectorNumberField(title: "Loop pitch", value: trochoidalPitch, suffix: "% radius")
                    .help("How far each loop steps forward, 5–100 % of the tool radius.")
            case .adaptive:
                InspectorNumberField(title: "Optimal load", value: adaptiveLoad, suffix: "% of Ø")
                    .help("Radial engagement the tool is kept at while clearing. Smaller values mean lighter cuts and more passes.")
                InspectorNote(text: adaptiveLoadNote)
            case .offset, .raster:
                EmptyView()
        }
    }
}

// MARK: - What the app doesn't offer (yet)

private extension OperationKind {

    /// `formFields` describes everything the engine can take. These parts have no home in
    /// `ToolpathData` yet, or are covered by another control.
    var hiddenFieldIDs: Set<String> {
        switch self {
        case .contour:
            // The side gets its own dedicated `ContourPicker` row above. Lead-in/out have their own rows:
            // `LeadInOutRow` + popover (stored on `OperationSettings.contourLeadIn/Out`). Holding tabs
            // have their own row and popover (`HoldingTabsEditor`) on `OperationSettings.contourTabs`.
            return ["entry", "contour.side", "contour.tabs", "contour.leadIn", "contour.leadOut"]
        case .pocket:
            // The clearing pattern gets its own dedicated picker in the Operation section with icon
            // glyphs, so the generic text-only field is hidden entirely, spiral direction
            // and trochoidal pitch included.
            return ["entry", "pattern"]
        case .slotting:
            // Only `.raster` makes sense until open-ended slots are derived. The depth per
            // pass is edited in the Z axis section, next to the other depths.
            return ["entry", "pattern", "slotting.depthPerPass"]
        case .drilling:
            // The peck depth is edited in the Z axis section (`PanelToolpathDetails.rowDepth`).
            return ["drilling.peckDepth"]
        case .counterbore:
            // The depth is edited in the Z axis section, as the End Z.
            return ["entry", "counterbore.depth"]
        case .engrave:
            // Same dedicated ramping row as the other operations with an entry.
            return ["entry"]
        case .chamfer:
            // The side gets its own dedicated `ContourPicker` row above.
            return ["chamfer.params.side"]
        default:
            return []
        }
    }

    static let hiddenCaseIDs: Set<String> = ["adaptive", "fromOpenEnd"]
}

// MARK: - Reusable controls

/// A labelled pop-up button for any string-backed enum.
struct EnumMenuPicker<Value: Hashable & CaseIterable & RawRepresentable>: View where Value.RawValue == String {
    let title: String
    @Binding var selection: Value

    var body: some View {
        InspectorRow(label: title) {
            Menu {
                ForEach(Array(Value.allCases), id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        if option == selection {
                            Label(option.rawValue, systemImage: "checkmark")
                        } else {
                            Text(option.rawValue)
                        }
                    }
                }
            } label: {
                InspectorMenuLabel {
                    Text(selection.rawValue)
                }
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
        }
    }
}

/// A labelled on/off switch.
struct ToggleField: View {
    let title: String
    @Binding var isOn: Bool
    /// Tooltip saying what the switch does, for the ones the label alone doesn't explain.
    var help: String? = nil

    var body: some View {
        let row = InspectorRow(label: title) {
            HStack(spacing: 8) {
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Text(isOn ? "On" : "Off")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        if let help {
            row.help(help)
        } else {
            row
        }
    }
}
