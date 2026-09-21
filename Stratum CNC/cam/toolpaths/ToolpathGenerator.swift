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

    /// Everything the engine needs, captured up front so the (slow) engine
    /// run can happen on a background thread without touching the canvas.
    struct Job: Sendable {
        let contours: [SC.Contour]
        let tool: SC.ToolParams
        let settings: SC.MachineSettings
        let operation: SC.MachiningOperation
        let startZ: Double
    }

    /// Validates the toolpath and resolves its shapes against the objects'
    /// *current* position/scale/rotation on the canvas. Cheap, but reads
    /// canvas state, so call it on the main thread; then hand the `Job` to `run`.
    static func prepare(for toolpath: ToolpathData, canvasState: D2_CanvasState) throws -> Job {

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

        logJobSummary(for: toolpath, contours: contours)

        return Job(contours: contours,
                   tool: makeTool(from: toolpath.tool),
                   settings: makeSettings(from: toolpath),
                   operation: makeOperation(from: toolpath),
                   startZ: toolpath.startZ)
    }

    /// The slow part: runs StratumCAM. Touches no shared state, so it's safe
    /// to call from any thread.
    static func run(_ job: Job) throws -> [SC.OutputToolpath] {
        let t0 = PerfLog.now()
        PerfLog.log("gen", "engine: started (\(job.contours.count) contour(s))")

        let outputs: [SC.OutputToolpath]
        do {
            outputs = try SCEngine().generateToolpaths(from: job.contours,
                                                       tool: job.tool,
                                                       settings: job.settings,
                                                       operation: job.operation)
        } catch {
            PerfLog.log("gen", "engine: FAILED after \(PerfLog.fmt(PerfLog.ms(since: t0))): \(message(for: error))")
            throw error
        }
        PerfLog.log("gen", "engine: finished in \(PerfLog.fmt(PerfLog.ms(since: t0)))")
        logStats(of: outputs, label: "engine output")

        let trimmed = outputs.map { droppingPasses(above: job.startZ, from: $0) }
        let before = outputs.reduce(0) { $0 + $1.passes.count }
        let after = trimmed.reduce(0) { $0 + $1.passes.count }
        if before != after {
            PerfLog.log("gen", "dropped \(before - after) pass(es) above startZ=\(job.startZ) (\(before) → \(after))")
        }
        return trimmed
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


// MARK: - Diagnostics (PerfLog)

private extension ToolpathGenerator {

    /// What we hand to the engine. `entities` is the number of line/arc pieces the
    /// contours are chained from — SVG curves are flattened to short lines on import,
    /// so a visually simple shape can still be tens of thousands of entities.
    static func logJobSummary(for toolpath: ToolpathData, contours: [SC.Contour]) {
        let entityCounts = contours.map { $0.entities.count }
        let totalEntities = entityCounts.reduce(0, +)
        let expectedPasses = toolpath.stepDown > 0
            ? Int((abs(toolpath.endZ - min(toolpath.startZ, 0)) / toolpath.stepDown).rounded(.up))
            : 0
        let ramp = toolpath.ramping.enabled
            ? "\(toolpath.ramping.type) angle=\(toolpath.ramping.angle)° length=\(toolpath.ramping.length)"
            : "off"

        PerfLog.log("gen", "job '\(toolpath.name)': \(toolpath.targets.count) shape(s) → \(contours.count) contour(s), "
                    + "\(totalEntities) entities (largest contour: \(entityCounts.max() ?? 0))")
        PerfLog.log("gen", "job '\(toolpath.name)': \(toolpath.contour) · tool Ø\(toolpath.tool.toolDiameter) · "
                    + "stepdown \(toolpath.stepDown) · stepover \(toolpath.stepOver) · Z \(toolpath.startZ)…\(toolpath.endZ) "
                    + "(≈\(expectedPasses) passes) · ramp: \(ramp)")
    }

    /// Size and shape of what the engine produced.
    static func logStats(of outputs: [SC.OutputToolpath], label: String) {
        var passes = 0
        var waypoints = 0
        var rapid = 0, linear = 0, arcCW = 0, arcCCW = 0
        var perPass: [Int] = []
        var waypointStride = 0

        for output in outputs {
            for pass in output.passes {
                passes += 1
                waypoints += pass.waypoints.count
                perPass.append(pass.waypoints.count)

                if waypointStride == 0, let first = pass.waypoints.first {
                    waypointStride = MemoryLayout.stride(ofValue: first)
                }
                for waypoint in pass.waypoints {
                    switch waypoint.motion {
                    case .rapid: rapid += 1
                    case .linear: linear += 1
                    case .arcCW: arcCW += 1
                    case .arcCCW: arcCCW += 1
                    }
                }
            }
        }

        let megabytes = Double(waypoints * waypointStride) / 1_048_576
        let average = passes > 0 ? waypoints / passes : 0
        PerfLog.log("gen", "\(label): \(outputs.count) toolpath(s), \(passes) pass(es), \(waypoints) waypoints "
                    + "(rapid \(rapid), linear \(linear), arcCW \(arcCW), arcCCW \(arcCCW))")
        PerfLog.log("gen", "\(label): waypoints/pass min \(perPass.min() ?? 0) · avg \(average) · max \(perPass.max() ?? 0) · "
                    + "first passes \(Array(perPass.prefix(6))) · ≈\(String(format: "%.0f", megabytes)) MB in memory "
                    + "(\(waypointStride) B per waypoint, arrays only)")
    }
}
