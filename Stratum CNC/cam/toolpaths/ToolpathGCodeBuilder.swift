//
//  ToolpathGCodeBuilder.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 08.09.2026.
//


import AppKit

enum ToolpathGCodeBuilder {

    enum BuildError: Error, LocalizedError {
        case noTarget
        case objectNotFound
        case pathIndexOutOfRange
        case emptyPath

        var errorDescription: String? {
            switch self {
            case .noTarget: return "This toolpath isn't assigned to a contour yet — select one on the canvas first."
            case .objectNotFound: return "The object this toolpath targets is no longer on the canvas."
            case .pathIndexOutOfRange: return "The targeted contour no longer exists on this object (was the file re-imported?)."
            case .emptyPath: return "The targeted contour has no drawable geometry."
            }
        }
    }

    /// Builds a complete G-code program for one toolpath, using the contour
    /// it targets (`toolpath.target`), resolved against the current canvas state.
    static func generate(for toolpath: ToolpathData, canvasState: D2_CanvasState, flattenTolerance: CGFloat = 0.05) throws -> String {

        guard let target = toolpath.target else { throw BuildError.noTarget }
        guard let object = canvasState.objects.first(where: { $0.id == target.objectID }) else {
            throw BuildError.objectNotFound
        }
        guard object.paths.indices.contains(target.pathIndex) else {
            throw BuildError.pathIndexOutOfRange
        }

        let localPath = object.paths[target.pathIndex]

        // Flatten in local (import) space, then map every point into world/
        // machine space via the object's *current* transform — same
        // convention `machineEntities` uses, so this always matches what's
        // drawn, however the object's been moved/resized/rotated since import.
        var subpaths = BezierPathFlattener.flatten([localPath], tolerance: flattenTolerance)
            .map { $0.map { object.worldPoint(fromLocal: $0) } }

        guard !subpaths.isEmpty, subpaths.contains(where: { $0.count > 1 }) else {
            throw BuildError.emptyPath
        }

        if toolpath.contour != .outline {
            let radius = CGFloat(toolpath.tool.toolDiameter / 2)
            let signedDistance = toolpath.contour == .outside ? radius : -radius
            subpaths = subpaths.map {
                PolygonOffset.offset($0.map { CGPoint(x: $0.x, y: $0.y) }, by: signedDistance)
                    .map { NSPoint(x: $0.x, y: $0.y) }
            }
        }

        return GCodeGenerator.generate(
            subpaths: subpaths,
            units: .millimeters,
            safeHeightZ: toolpath.safeZ,
            passDepths: passDepths(startZ: toolpath.startZ, endZ: toolpath.endZ, stepDown: toolpath.stepDown),
            feedRateCut: Int(toolpath.feedRate),
            feedRatePlunge: Int(toolpath.plungeRate),
            spindleSpeed: toolpath.spindleRPM,
            ramp: toolpath.ramping,
            preamble: ["; \(toolpath.name) — T\(toolpath.tool.displayName) \u{00D8}\(toolpath.tool.toolDiameter)mm"]
        )
    }

    /// Depth-of-cut passes from `startZ` down to `endZ` in `stepDown`
    /// increments, always ending exactly on `endZ` (the final pass is
    /// whatever remainder is left, even if smaller than a full stepDown).
    static func passDepths(startZ: Double, endZ: Double, stepDown: Double) -> [Double] {
        guard endZ < startZ, stepDown > 0 else { return [endZ] }
        var depths: [Double] = []
        var z = startZ
        while z - stepDown > endZ {
            z -= stepDown
            depths.append(z)
        }
        depths.append(endZ)
        return depths
    }
}