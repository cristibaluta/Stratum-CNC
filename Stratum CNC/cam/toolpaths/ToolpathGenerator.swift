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
        case invalidOption(String)

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
            case .invalidOption(let message):
                return message
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
        /// The selected shapes are slot *outlines*: turn each into the centre line the
        /// engine's `.slotting` expects before generating (see `run`).
        let derivesSlotCenterline: Bool
    }

    /// Validates the toolpath and resolves its shapes against the objects'
    /// *current* position/scale/rotation on the canvas. Cheap, but reads
    /// canvas state, so call it on the main thread; then hand the `Job` to `run`.
    static func prepare(for toolpath: ToolpathData, canvasState: D2_CanvasState) throws -> Job {

        guard !toolpath.targets.isEmpty else {
            throw GenerationError.noShapes
        }
        try validateOptions(of: toolpath)

        let operation = makeOperation(from: toolpath)

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
                   tool: makeTool(from: toolpath.tool, for: toolpath.operation.kind),
                   settings: makeSettings(from: toolpath),
                   operation: operation,
                   startZ: toolpath.startZ,
                   derivesSlotCenterline: toolpath.operation.kind == .slotting
                       && toolpath.operation.slotSource == .outline)
    }

    /// The slow part: runs StratumCAM. Touches no shared state, so it's safe
    /// to call from any thread.
    static func run(_ job: Job) throws -> [SC.OutputToolpath] {
        let t0 = PerfLog.now()
        PerfLog.log("gen", "engine: started (\(job.contours.count) contour(s))")

        let engine = SCEngine()
        let outputs: [SC.OutputToolpath]
        do {
            var contours = job.contours
            if job.derivesSlotCenterline {
                contours = try contours.map { (outline: SC.Contour) -> SC.Contour in
                    // A little looser than the library's 0.001 mm default: hand-drawn (and
                    // scaled or rotated) rectangles are never exact to a micron.
                    guard let centerline = engine.rectangleSlotCenterline(fromBoundary: outline,
                                                                           tool: job.tool,
                                                                           tolerance: 0.05) else {
                        throw GenerationError.invalidOption(
                            "A selected slot outline isn't a straight-sided rectangle exactly as wide as the tool "
                            + "(Ø\(job.tool.diameter) mm). Resize it, or set \"Selection is\" to \"Centre line\"."
                        )
                    }
                    return centerline
                }
                PerfLog.log("gen", "derived \(contours.count) slot centre line(s) from the selected outlines")
            }

            outputs = try engine.generateToolpaths(from: contours,
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

    /// A message fit for showing under the Generate button. `operation` (the operation the
    /// error came from) lets a few generic engine errors say what actually went wrong.
    static func message(for error: Error, operation: OperationKind? = nil) -> String {
        if let error = error as? GenerationError {
            return error.errorDescription ?? "Couldn't generate the toolpath."
        }
        if let error = error as? SC.Error {
            switch error {
            case .contourNotClosed:
                return "This operation needs closed shapes, but a selected shape is open."
            case .invalidContour:
                if operation == .threadMilling {
                    return "Thread milling needs each selected shape to be one closed circle (the existing hole). "
                        + "SVG circles are stored as lines and aren't recognised — use a DXF or drill-file circle."
                }
                return "A selected shape has no usable geometry."
            case .missingDrillPoint:
                return "A selected shape isn't a point or a closed circle. "
                    + "SVG circles are stored as lines and aren't recognised — use a DXF or drill-file circle."
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

    static func makeTool(from tool: Tool, for kind: OperationKind) -> SC.ToolParams {
        let vAngle = tool.tipAngle.map { Double($0) }

        // `Tool.type` is not mapped yet: everything is a flat end mill, except for a chamfer,
        // the one operation that looks at the tool type — it derives its depth from a V-bit's
        // included angle. A tool with a tip angle is taken as a V-bit there.
        let type: SC.ToolType = (kind == .chamfer && (vAngle ?? 0) > 0) ? .vBit : .flatEndMill

        return SC.ToolParams(id: tool.id,
                             name: tool.name,
                             type: type,
                             diameter: Double(tool.toolDiameter),
                             vAngle: vAngle,
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
        // A counterbore has its own depth (and no End Z field); everything else cuts down to End Z.
        let depth = toolpath.operation.kind == .counterbore
            ? toolpath.operation.counterboreDepth
            : toolpath.endZ

        return SC.MachineSettings(cutting: cutting,
                                  safeZ: toolpath.safeZ,
                                  retractZ: min(1.0, toolpath.safeZ),
                                  targetDepth: abs(depth))
    }

    /// Rejects option values the engine can't work with, with a message the user can act on.
    static func validateOptions(of toolpath: ToolpathData) throws {
        let options = toolpath.operation

        if options.kind.usesEndZ {
            guard toolpath.endZ < toolpath.startZ else {
                throw GenerationError.invalidDepth
            }
        }

        switch options.kind {
        case .contour, .engrave:
            break
        case .pocket:
            if options.pocketPattern == .trochoidal,
               !(5...100).contains(options.pocketTrochoidalPitch) {
                // Below ~5 % the loops get so tight that the path explodes in size.
                throw GenerationError.invalidOption("The trochoidal loop pitch must be between 5 % and 100 % of the tool radius.")
            }
        case .facing:
            guard options.facingExtension >= 0 else {
                throw GenerationError.invalidOption("The facing extension can't be negative.")
            }
        case .slotting:
            guard options.slotDepthPerPass > 0 else {
                throw GenerationError.invalidOption("Depth per pass must be greater than 0.")
            }
        case .drilling:
            if options.drillUsesPecking, options.drillPeckDepth <= 0 {
                throw GenerationError.invalidOption("The peck depth must be greater than 0.")
            }
        case .counterbore:
            guard options.counterboreDepth > 0 else {
                throw GenerationError.invalidOption("The counterbore depth must be greater than 0.")
            }
            guard options.counterboreDiameter > Double(toolpath.tool.toolDiameter) else {
                throw GenerationError.invalidOption("The counterbore diameter must be larger than the tool (Ø\(toolpath.tool.toolDiameter) mm).")
            }
        case .boring:
            guard options.boreTargetDiameter > 0 else {
                throw GenerationError.invalidOption("The finished diameter must be greater than 0.")
            }
            if options.boreUsesDwell, options.boreDwellTime < 0 {
                throw GenerationError.invalidOption("The dwell time can't be negative.")
            }
        case .threadMilling:
            guard options.threadPitch > 0 else {
                throw GenerationError.invalidOption("The thread pitch must be greater than 0.")
            }
            guard options.threadTargetDiameter > 0 else {
                throw GenerationError.invalidOption("The thread diameter must be greater than 0.")
            }
            guard options.threadRadialPasses >= 1 else {
                throw GenerationError.invalidOption("The thread needs at least 1 radial pass.")
            }
        case .chamfer:
            guard options.chamferWidth > 0 else {
                throw GenerationError.invalidOption("The chamfer width must be greater than 0.")
            }
            if options.chamferUsesDepth {
                guard options.chamferDepth > 0 else {
                    throw GenerationError.invalidOption("The chamfer depth must be greater than 0.")
                }
            } else if (toolpath.tool.tipAngle ?? 0) <= 0 {
                throw GenerationError.invalidOption("A chamfer needs a V-bit: pick a tool with a tip angle, or turn on Fixed depth.")
            }
        }
    }

    /// The toolpath's operation and options as StratumCAM's `SC.MachiningOperation`.
    ///
    /// Not offered: `PocketClearingPattern.adaptive` (its engine code is a `fatalError`), the
    /// slot patterns `.trochoidal`/`.adaptive` and `EntryStrategy.fromOpenEnd` (they only make
    /// sense for slot outlines open at one or both ends, which the app doesn't derive yet), and
    /// lead-in/out and holding tabs on contours.
    ///
    /// Internal (unlike the rest of this extension) because `ToolpathData.machiningOperation`
    /// reads it to build the form.
    internal static func makeOperation(from toolpath: ToolpathData) -> SC.MachiningOperation {
        let options = toolpath.operation
        let direction = makeDirection(from: options.direction)
        let entry = makeEntry(from: toolpath.ramping)

        switch options.kind {

        case .contour:
            let side: SC.CutSide
            switch toolpath.contour {
            case .inside:  side = .inside
            case .outside: side = .outside
            case .outline: side = .onContour
            }
            return .contour(side: side,
                            direction: direction,
                            entry: entry,
                            leadIn: nil,
                            leadOut: nil,
                            tabs: [])

        case .pocket:
            return .pocket(direction: direction,
                           pattern: makePocketPattern(from: options),
                           entry: entry)

        case .facing:
            return .facing(direction: direction,
                           extensionLength: options.facingExtension)

        case .slotting:
            // The pattern only matters together with `.fromOpenEnd` entry; for a plunge, ramp or
            // helix entry the engine just traces the centre line.
            return .slotting(depthPerPass: options.slotDepthPerPass,
                             pattern: .raster,
                             entry: entry)

        case .engrave:
            return .engrave

        case .drilling:
            return .drilling(peckDepth: options.drillUsesPecking ? options.drillPeckDepth : nil)

        case .counterbore:
            return .counterbore(diameter: options.counterboreDiameter,
                                depth: options.counterboreDepth,
                                direction: direction,
                                entry: entry)

        case .boring:
            return .boring(targetDiameter: options.boreTargetDiameter,
                           dwellTime: options.boreUsesDwell ? options.boreDwellTime : nil,
                           shiftRetract: options.boreShiftRetract)

        case .threadMilling:
            return .threadMilling(pitch: options.threadPitch,
                                  isInternal: options.threadIsInternal,
                                  direction: options.threadHandedness == .rightHand ? .rightHand : .leftHand,
                                  radialPasses: options.threadRadialPasses,
                                  targetDiameter: options.threadTargetDiameter)

        case .chamfer:
            let side: SC.CutSide
            switch options.chamferSide {
            case .outside:   side = .outside
            case .inside:    side = .inside
            case .onContour: side = .onContour
            }
            let params = SC.ChamferParams(width: options.chamferWidth,
                                          depth: options.chamferUsesDepth ? options.chamferDepth : nil,
                                          side: side,
                                          direction: direction)
            return .chamfer(params: params)
        }
    }

    static func makePocketPattern(from options: OperationSettings) -> SC.PocketClearingPattern {
        switch options.pocketPattern {
        case .offset:
            return .offset
        case .raster:
            return .raster
        case .spiral:
            return .spiral(direction: options.pocketSpiral == .outsideIn ? .outsideIn : .insideOut)
        case .trochoidal:
            // `radialEngagement` is a fraction of the tool radius; the pocket ignores `loopRadius`.
            return .trochoidal(settings: SC.TrochoidalSettings(radialEngagement: options.pocketTrochoidalPitch / 100,
                                                               loopRadius: 0))
        }
    }

    static func makeDirection(from direction: CutDirectionOption) -> SC.CutDirection {
        switch direction {
        case .climb:        return .climb
        case .conventional: return .conventional
        }
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
        let operation = toolpath.operation.kind == .contour
            ? "contour/\(toolpath.contour)"
            : "\(toolpath.operation.kind)"
        PerfLog.log("gen", "job '\(toolpath.name)': \(operation) · tool Ø\(toolpath.tool.toolDiameter) · "
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
