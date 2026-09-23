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
//   - `.adaptive` pocket pattern: the engine still stops with `fatalError` on it
//

import Foundation
import StratumCAM

extension ToolpathData {

    var machiningOperation: SC.MachiningOperation {
        get { ToolpathGenerator.makeOperation(from: self) }
        set { apply(newValue) }
    }

    private mutating func apply(_ newValue: SC.MachiningOperation) {
        switch newValue {

            case .facing(let direction, let extensionLength):
                operation.direction = CutDirectionOption(direction)
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

            case .contour(let side, let direction, _, _, _, _):
                contour = ContourType(side)
                operation.direction = CutDirectionOption(direction)

            case .pocket(let direction, let pattern, _):
                operation.direction = CutDirectionOption(direction)
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
                    case .adaptive:
                        break
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
                operation.chamferSide = ChamferSide(params.side)
                operation.direction = CutDirectionOption(params.direction)

            case .boring(let targetDiameter, let dwellTime, let shiftRetract):
                operation.boreTargetDiameter = targetDiameter
                operation.boreUsesDwell = dwellTime != nil
                if let dwellTime {
                    operation.boreDwellTime = dwellTime
                }
                operation.boreShiftRetract = shiftRetract

            case .counterbore(let diameter, let depth, let direction, _):
                operation.counterboreDiameter = diameter
                operation.counterboreDepth = depth
                operation.direction = CutDirectionOption(direction)
        }
    }
}

// MARK: - StratumCAM -> app enums

private extension CutDirectionOption {
    init(_ direction: SC.CutDirection) {
        self = direction == .conventional ? .conventional : .climb
    }
}

private extension ContourType {
    init(_ side: SC.CutSide) {
        switch side {
            case .inside:    self = .inside
            case .outside:   self = .outside
            case .onContour: self = .outline
        }
    }
}

private extension ChamferSide {
    init(_ side: SC.CutSide) {
        switch side {
            case .inside:    self = .inside
            case .outside:   self = .outside
            case .onContour: self = .onContour
        }
    }
}
