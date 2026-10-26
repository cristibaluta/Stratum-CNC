//
//  ToolpathData+Operation.swift
//  Stratum CNC
//
//  Lets the form built by `SC.MachiningOperation.formFields` edit a `ToolpathData`.
//
//  Reading goes through `ToolpathGenerator.makeOperation(from:)`, the same translation the
//  generator uses, so the form always shows exactly what would be generated. Writing is its
//  inverse: whatever `formFields` hands back is stored in the app's own (Codable) settings.
//
//  What is deliberately *not* written back, because the app keeps it elsewhere or doesn't
//  offer it:
//   - the entry strategy: it lives in `ToolpathData.ramping`, edited by the ramping editor
//   - contour lead-in / lead-out / holding tabs, and the slot clearing pattern: not stored yet
//

import Foundation
import StratumCAM

extension ToolpathData {

    var machiningOperation: SC.MachiningOperation {
        get { ToolpathGenerator.makeOperation(from: self) }
        set { apply(newValue) }
    }

    private mutating func apply(_ newValue: SC.MachiningOperation) {
        // Every operation that has a direction stores it in the same place.
        if let direction = newValue.direction {
            operation.direction = CutDirectionOption(direction)
        }

        switch newValue {

            case .facing(_, let extensionLength):
                operation.facingExtension = extensionLength

            case .slotting(let depthPerPass, _, _):
                operation.slotDepthPerPass = depthPerPass

            case .threadMilling(let pitch, let isInternal, let direction, let radialPasses, let targetDiameter):
                operation.threadPitch = pitch
                operation.threadIsInternal = isInternal
                operation.threadHandedness = direction == .leftHand ? .leftHand : .rightHand
                operation.threadRadialPasses = radialPasses
                operation.threadTargetDiameter = targetDiameter

            case .engrave:
                break

            case .contour(let side, _, _, _, _, _):
                contour = side

            case .pocket(_, let pattern, _):
                switch pattern {
                    case .offset:
                        operation.pocketPattern = .offset
                    case .raster:
                        operation.pocketPattern = .raster
                    case .spiral(let spiralDirection):
                        operation.pocketPattern = .spiral
                        operation.pocketSpiral = spiralDirection == .insideOut ? .insideOut : .outsideIn
                    case .trochoidal(let settings):
                        operation.pocketPattern = .trochoidal
                        // The app keeps the loop pitch as a percentage of the tool radius.
                        operation.pocketTrochoidalPitch = settings.radialEngagement * 100
                    case .concentric(let spiralDirection):
                        operation.pocketPattern = .concentric
                        operation.pocketSpiral = spiralDirection == .insideOut ? .insideOut : .outsideIn
                    case .adaptive(let settings):
                        operation.pocketPattern = .adaptive
                        operation.pocketAdaptiveLoad = settings.optimalLoad
                }

            case .drilling(let peckDepth):
                operation.drillUsesPecking = peckDepth != nil
                if let peckDepth {
                    operation.drillPeckDepth = peckDepth
                }

            case .chamfer(let params):
                operation.chamferWidth = params.width
                operation.chamferUsesDepth = params.depth != nil
                if let depth = params.depth {
                    operation.chamferDepth = depth
                }
                operation.chamferSide = params.side

            case .boring(let targetDiameter, let dwellTime, let shiftRetract):
                operation.boreTargetDiameter = targetDiameter
                operation.boreUsesDwell = dwellTime != nil
                if let dwellTime {
                    operation.boreDwellTime = dwellTime
                }
                operation.boreShiftRetract = shiftRetract

            case .counterbore(let diameter, let depth, _, _):
                operation.counterboreDiameter = diameter
                operation.counterboreDepth = depth
        }
    }
}

// MARK: - StratumCAM -> app enums

private extension CutDirectionOption {
    init(_ direction: SC.CutDirection) {
        self = direction == .conventional ? .conventional : .climb
    }
}
