//
//  ToolpathGenerator.swift
//  Stratum CNC
//
//  Turns a `ToolpathData` (what the user configured in a toolpath cell) into
//  real toolpaths by calling StratumCAM's `SCEngine.generateToolpaths`.
//

import Foundation
import StratumCAM

enum ToolpathGenerator {

    enum GenerationError: Error, LocalizedError {
        case noShapes
        case invalidDepth
        case objectNotFound
        case shapeNotFound
        case noGeometry

        var errorDescription: String? {
            switch self {
            case .noShapes:
                return "No shapes selected — use \"Select shapes\" and click them on the canvas."
            case .invalidDepth:
                return "End Z must be below Start Z."
            case .objectNotFound:
                return "A selected shape belongs to an object that is no longer on the canvas."
            case .shapeNotFound:
                return "A selected shape no longer exists on its object (was the file re-imported?)."
            case .noGeometry:
                return "The selected shapes have no machinable geometry."
            }
        }
    }

    /// Generates the toolpaths for every shape in `toolpath.targets`, resolved
    /// against the objects' *current* position/scale/rotation on the canvas.
    static func generate(for toolpath: ToolpathData, canvasState: D2_CanvasState) throws -> [SC.OutputToolpath] {

        guard !toolpath.targets.isEmpty else {
            throw GenerationError.noShapes
        }
        guard toolpath.endZ < toolpath.startZ else {
            throw GenerationError.invalidDepth
        }

        var contours: [SC.Contour] = []
        for target in toolpath.targets {
            guard let object = canvasState.object(withID: target.objectID) else {
                throw GenerationError.objectNotFound
            }
            guard object.paths.indices.contains(target.pathIndex) else {
                throw GenerationError.shapeNotFound
            }
            contours += object.machineContours(forPathAt: target.pathIndex)
        }
        guard !contours.isEmpty else {
            throw GenerationError.noGeometry
        }

        let outputs = try SCEngine().generateToolpaths(from: contours,
                                                       tool: makeTool(from: toolpath.tool),
                                                       settings: makeSettings(from: toolpath),
                                                       operation: makeOperation(from: toolpath))

        return outputs.map { droppingPasses(above: toolpath.startZ, from: $0) }
    }

    /// A message fit for showing under the Generate button.
    static func message(for error: Error) -> String {
        if let error = error as? GenerationError {
            return error.errorDescription ?? "Couldn't generate the toolpath."
        }
        if let error = error as? SC.Error {
            switch error {
            case .contourNotClosed:
                return "This operation needs closed shapes, but a selected shape is open."
            case .invalidContour:
                return "A selected shape has no usable geometry."
            case .missingDrillPoint:
                return "A selected shape has no drill point (expected a point or a closed circle)."
            case .toolIncompatible:
                return "The selected tool can't perform this operation."
            case .invalidParameter(let name):
                return "Invalid parameter: \(name)."
            case .geometryCollapsed:
                return "The tool is too large for the selected shapes — nothing is left after offsetting."
            @unknown default:
                return "Couldn't generate the toolpath (\(error))."
            }
        }
        return error.localizedDescription
    }
}

// MARK: - App model -> StratumCAM model

private extension ToolpathGenerator {

    static func makeTool(from tool: Tool) -> SC.ToolParams {
        // `Tool.type` is not mapped yet: everything is treated as a flat end
        // mill. When V-bits / drills / thread mills can be created in the app,
        // switch on `tool.type` here to pick the matching `SC.ToolType`.
        SC.ToolParams(id: tool.id,
                      name: tool.name,
                      type: .flatEndMill,
                      diameter: Double(tool.toolDiameter),
                      vAngle: tool.tipAngle.map { Double($0) },
                      fluteLength: Double(tool.length!))
    }

    static func makeSettings(from toolpath: ToolpathData) -> SC.MachineSettings {
        let diameter = Double(toolpath.tool.toolDiameter)

        // The app stores stepover in mm, the library as a fraction of the tool diameter.
        let stepoverFraction = diameter > 0 ? min(max(toolpath.stepOver / diameter, 0.1), 0.95) : 0.4

        let cutting = SC.CuttingData(spindleSpeed: Double(toolpath.spindleRPM),
                                     feedRate: toolpath.feedRate,
                                     plungeRate: toolpath.plungeRate,
                                     stepdown: toolpath.stepDown,
                                     stepoverPercentage: stepoverFraction)

        // The library measures depth down from the top of the stock (Z0).
        // `startZ` is handled afterwards by `droppingPasses(above:from:)`.
        return SC.MachineSettings(cutting: cutting,
                                  safeZ: toolpath.safeZ,
                                  retractZ: min(1.0, toolpath.safeZ),
                                  targetDepth: abs(toolpath.endZ))
    }

    static func makeOperation(from toolpath: ToolpathData) -> SC.MachiningOperation {
        let side: SC.CutSide
        switch toolpath.contour {
        case .inside:  side = .inside
        case .outside: side = .outside
        case .outline: side = .onContour
        }

        return .contour(side: side,
                        direction: .climb,
                        entry: makeEntry(from: toolpath.ramping),
                        leadIn: nil,
                        leadOut: nil,
                        tabs: [])
    }

    static func makeEntry(from ramping: RampingSettings) -> SC.EntryStrategy {
        guard ramping.enabled else {
            return .plunge
        }
        switch ramping.type {
        case .none:
            return .plunge
        case .linear:
            // The ramp length follows from the angle and the stepdown
            // (see RampingEditor), so only the angle goes to the library.
            return .ramp(angleDegrees: ramping.angle)
        case .helix:
            // For a helix the app's "ramp length" is the spiral's diameter
            // (see HelixTopView), the library wants a radius.
            return .helix(radius: max(ramping.length, 0.1) / 2, rampAngleDegrees: ramping.angle)
        }
    }

    /// The library always starts cutting from the top of the stock (Z0). When
    /// the user's Start Z is lower than that, the passes that would only cut
    /// air above it are dropped so the job effectively starts at Start Z.
    static func droppingPasses(above startZ: Double, from toolpath: SC.OutputToolpath) -> SC.OutputToolpath {
        guard startZ < 0 else {
            return toolpath
        }

        let kept = toolpath.passes.filter { $0.depthZ <= startZ + 1e-9 }
        guard kept.count != toolpath.passes.count else {
            return toolpath
        }

        var result = toolpath
        result.passes = kept.enumerated().map { index, pass in
            SC.ToolpathPass(passIndex: index, depthZ: pass.depthZ, waypoints: pass.waypoints)
        }
        return result
    }
}
