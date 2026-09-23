//
//  MachiningOperations+Ext.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 23.09.2026.
//

import Foundation
import StratumCAM

extension SC.MachiningOperation {

    /// Builds the list of user-editable fields for this specific operation
    ///
    /// `onChange` is called with the fully rebuilt `MachiningOperation`
    /// every time any field, at any nesting depth, changes -- the caller
    /// (typically a view model) is responsible for writing that value back
    /// into whatever holds the operation, e.g. `OutputToolpath.operation`.
    public func formFields(onChange: @escaping (SC.MachiningOperation) -> Void) -> [SC.ParameterField] {
        switch self {

            case .facing(let direction, let extensionLength):
                return [
                    .choice(SC.cutDirectionChoice(id: "facing.direction", current: direction, onChange: {
                        onChange(.facing(direction: $0, extensionLength: extensionLength))
                    })),
                    .double(.init(id: "facing.extensionLength", label: "Extension Length", unit: "mm",
                                  range: 0.0...50.0, value: extensionLength, onChange: {
                        onChange(.facing(direction: direction, extensionLength: $0))
                    }))
                    // No stepover: facing derives row spacing from the tool's own
                    // diameter (SCEngine.facingStepover), so there's nothing to expose.
                ]

            case .slotting(let depthPerPass, let pattern, let entry):
                return [
                    .double(.init(id: "slotting.depthPerPass", label: "Depth Per Pass", unit: "mm",
                                  range: 0.05...20.0, value: depthPerPass, onChange: {
                        onChange(.slotting(depthPerPass: $0, pattern: pattern, entry: entry))
                    })),
                    pattern.formField(onChange: { onChange(.slotting(depthPerPass: depthPerPass, pattern: $0, entry: entry)) }),
                    entry.formField(onChange: { onChange(.slotting(depthPerPass: depthPerPass, pattern: pattern, entry: $0)) })
                ]

            case .threadMilling(let pitch, let isInternal, let direction, let radialPasses, let targetDiameter):
                return [
                    .double(.init(id: "threadMilling.pitch", label: "Pitch", unit: "mm",
                                  range: 0.1...10.0, value: pitch, onChange: {
                        onChange(.threadMilling(pitch: $0, isInternal: isInternal, direction: direction,
                                                 radialPasses: radialPasses, targetDiameter: targetDiameter))
                    })),
                    .bool(.init(id: "threadMilling.isInternal", label: "Internal Thread", value: isInternal, onChange: {
                        onChange(.threadMilling(pitch: pitch, isInternal: $0, direction: direction,
                                                 radialPasses: radialPasses, targetDiameter: targetDiameter))
                    })),
                    .choice(SC.threadDirectionChoice(id: "threadMilling.direction", current: direction, onChange: {
                        onChange(.threadMilling(pitch: pitch, isInternal: isInternal, direction: $0,
                                                 radialPasses: radialPasses, targetDiameter: targetDiameter))
                    })),
                    // Must be >= 1; the last pass always lands exactly on targetDiameter.
                    .int(.init(id: "threadMilling.radialPasses", label: "Radial Passes",
                               range: 1...6, value: radialPasses, onChange: {
                        onChange(.threadMilling(pitch: pitch, isInternal: isInternal, direction: direction,
                                                 radialPasses: $0, targetDiameter: targetDiameter))
                    })),
                    .double(.init(id: "threadMilling.targetDiameter", label: "Target Diameter", unit: "mm",
                                  range: 0.5...200.0, value: targetDiameter, onChange: {
                        onChange(.threadMilling(pitch: pitch, isInternal: isInternal, direction: direction,
                                                 radialPasses: radialPasses, targetDiameter: $0))
                    }))
                ]

            case .engrave:
                // No operation-specific parameters at all -- engrave just
                // follows the selected geometry with the tool's own compensation.
                return []

            case .contour(let side, let direction, let entry, let leadIn, let leadOut, let tabs):
                return [
                    .choice(SC.cutSideChoice(id: "contour.side", current: side, onChange: {
                        onChange(.contour(side: $0, direction: direction, entry: entry, leadIn: leadIn, leadOut: leadOut, tabs: tabs))
                    })),
                    .choice(SC.cutDirectionChoice(id: "contour.direction", current: direction, onChange: {
                        onChange(.contour(side: side, direction: $0, entry: entry, leadIn: leadIn, leadOut: leadOut, tabs: tabs))
                    })),
                    entry.formField(onChange: {
                        onChange(.contour(side: side, direction: direction, entry: $0, leadIn: leadIn, leadOut: leadOut, tabs: tabs))
                    }),
                    SC.LeadInOut.optionalFormField(idPrefix: "contour.leadIn", label: "Lead-In", current: leadIn, onChange: {
                        onChange(.contour(side: side, direction: direction, entry: entry, leadIn: $0, leadOut: leadOut, tabs: tabs))
                    }),
                    SC.LeadInOut.optionalFormField(idPrefix: "contour.leadOut", label: "Lead-Out", current: leadOut, onChange: {
                        onChange(.contour(side: side, direction: direction, entry: entry, leadIn: leadIn, leadOut: $0, tabs: tabs))
                    }),
                    .list(.init(
                        id: "contour.tabs",
                        label: "Holding Tabs",
                        items: tabs.map { tab in
                            .init(id: tab.id.uuidString, fields: [
                                .double(.init(id: "contour.tabs.\(tab.id).position", label: "Position", unit: "ratio (0-1)",
                                              range: 0.0...1.0, value: tab.positionRatio, onChange: { newValue in
                                    var newTabs = tabs
                                    if let idx = newTabs.firstIndex(where: { $0.id == tab.id }) { newTabs[idx].positionRatio = newValue }
                                    onChange(.contour(side: side, direction: direction, entry: entry, leadIn: leadIn, leadOut: leadOut, tabs: newTabs))
                                })),
                                .double(.init(id: "contour.tabs.\(tab.id).width", label: "Width", unit: "mm",
                                              range: 1.0...20.0, value: tab.width, onChange: { newValue in
                                    var newTabs = tabs
                                    if let idx = newTabs.firstIndex(where: { $0.id == tab.id }) { newTabs[idx].width = newValue }
                                    onChange(.contour(side: side, direction: direction, entry: entry, leadIn: leadIn, leadOut: leadOut, tabs: newTabs))
                                })),
                                .double(.init(id: "contour.tabs.\(tab.id).height", label: "Height", unit: "mm",
                                              range: 0.1...10.0, value: tab.height, onChange: { newValue in
                                    var newTabs = tabs
                                    if let idx = newTabs.firstIndex(where: { $0.id == tab.id }) { newTabs[idx].height = newValue }
                                    onChange(.contour(side: side, direction: direction, entry: entry, leadIn: leadIn, leadOut: leadOut, tabs: newTabs))
                                }))
                            ])
                        },
                        onAdd: {
                            var newTabs = tabs
                            newTabs.append(SC.HoldingTab(positionRatio: 0.5))
                            onChange(.contour(side: side, direction: direction, entry: entry, leadIn: leadIn, leadOut: leadOut, tabs: newTabs))
                        },
                        onRemove: { tabId in
                            var newTabs = tabs
                            newTabs.removeAll { $0.id.uuidString == tabId }
                            onChange(.contour(side: side, direction: direction, entry: entry, leadIn: leadIn, leadOut: leadOut, tabs: newTabs))
                        }
                    ))
                ]

            case .pocket(let direction, let pattern, let entry):
                return [
                    .choice(SC.cutDirectionChoice(id: "pocket.direction", current: direction, onChange: {
                        onChange(.pocket(direction: $0, pattern: pattern, entry: entry))
                    })),
                    pattern.formField(onChange: { onChange(.pocket(direction: direction, pattern: $0, entry: entry)) }),
                    entry.formField(onChange: { onChange(.pocket(direction: direction, pattern: pattern, entry: $0)) })
                ]

            case .drilling(let peckDepth):
                return [
                    .optionalDouble(.init(id: "drilling.peckDepth", label: "Peck Depth", unit: "mm",
                                  range: 0.05...20.0, defaultValueWhenEnabled: 1.0, value: peckDepth, onChange: {
                        onChange(.drilling(peckDepth: $0))
                    }))
                ]

            case .chamfer(let params):
                return [
                    .group(.init(id: "chamfer.params", label: "Chamfer",
                                 fields: params.formFields(idPrefix: "chamfer.params", onChange: { onChange(.chamfer(params: $0)) })))
                ]

            case .boring(let targetDiameter, let dwellTime, let shiftRetract):
                return [
                    .double(.init(id: "boring.targetDiameter", label: "Target Diameter", unit: "mm",
                                  range: 0.5...200.0, value: targetDiameter, onChange: {
                        onChange(.boring(targetDiameter: $0, dwellTime: dwellTime, shiftRetract: shiftRetract))
                    })),
                    .optionalDouble(.init(id: "boring.dwellTime", label: "Dwell Time", unit: "s",
                                  range: 0.1...10.0, defaultValueWhenEnabled: 1.0, value: dwellTime, onChange: {
                        onChange(.boring(targetDiameter: targetDiameter, dwellTime: $0, shiftRetract: shiftRetract))
                    })),
                    .bool(.init(id: "boring.shiftRetract", label: "Shift Before Retract", value: shiftRetract, onChange: {
                        onChange(.boring(targetDiameter: targetDiameter, dwellTime: dwellTime, shiftRetract: $0))
                    }))
                ]

            case .counterbore(let diameter, let depth, let direction, let entry):
                return [
                    .double(.init(id: "counterbore.diameter", label: "Diameter", unit: "mm",
                                  range: 1.0...100.0, value: diameter, onChange: {
                        onChange(.counterbore(diameter: $0, depth: depth, direction: direction, entry: entry))
                    })),
                    .double(.init(id: "counterbore.depth", label: "Depth", unit: "mm",
                                  range: 0.1...50.0, value: depth, onChange: {
                        onChange(.counterbore(diameter: diameter, depth: $0, direction: direction, entry: entry))
                    })),
                    .choice(SC.cutDirectionChoice(id: "counterbore.direction", current: direction, onChange: {
                        onChange(.counterbore(diameter: diameter, depth: depth, direction: $0, entry: entry))
                    })),
                    entry.formField(onChange: {
                        onChange(.counterbore(diameter: diameter, depth: depth, direction: direction, entry: $0))
                    })
                ]
        }
    }

    /// Display name for the operation case itself, for a picker that lets the
    /// user choose *which* operation to configure before `formFields` renders
    /// its parameters. Seeds each case with the same defaults used by
    /// `formFields`'s own `onSelect` closures where applicable.
    public var displayName: String {
        switch self {
            case .facing: return "Facing"
            case .slotting: return "Slotting"
            case .threadMilling: return "Thread Milling"
            case .engrave: return "Engrave"
            case .contour: return "Contour"
            case .pocket: return "Pocket"
            case .drilling: return "Drilling"
            case .chamfer: return "Chamfer"
            case .boring: return "Boring"
            case .counterbore: return "Counterbore"
        }
    }
}
