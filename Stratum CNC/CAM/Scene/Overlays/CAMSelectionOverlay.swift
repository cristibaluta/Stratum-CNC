//
//  CAMSelectionOverlay.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.09.2026.
//
//  What `D2_ObjectNode` draws on top of a selected object — the dashed
//  bounding box and the rotation-center handle — as `RenderObject`s. The
//  handle isn't decoration: it's the grab point for drag-to-move (see
//  `CAMCanvasInteraction`), so it has to exist in the Metal view for that
//  interaction to be discoverable at all.
//
//  Both are placed through `D2_Object.worldPoint(fromLocal:)`, the same
//  mapping the shapes themselves go through, so they stay glued to the
//  object however it's moved, scaled or rotated.
//

import Foundation
import CoreGraphics

enum CAMSelectionOverlay {

    /// Dash length in points on screen (Metal dashes are on/off runs of this length), so the box
    /// looks the same at any zoom. `D2_ObjectNode` uses a [6, 4] pattern; close enough for now —
    /// visual parity is step 5.
    static let dashLength: Float = 6

    // Same numbers as `CenterShapeLayer`, in the object's local units, so
    // the handle scales with the object exactly as it does today.
    private static let handleRadius: CGFloat = 3.5
    private static let handleCrossSize: CGFloat = 7
    private static let handleSegments = 24

    /// Dashed box + handle for one selected object. Handle first: with all
    /// of this at z = 0, the first-drawn line wins where two coincide, and
    /// the handle should be on top.
    static func renderObjects(for object: D2_Object,
                              boxColor: SIMD4<Float>,
                              handleColor: SIMD4<Float>) -> [RenderObject] {
        [rotationHandle(for: object, color: handleColor),
         selectionBox(for: object, color: boxColor)]
    }

    /// What a STEP model selected in the objects list gets, in the same look as a selected
    /// shape: the dashed box of its footprint and the handle at its middle, which is what
    /// the mouse grabs to move it (see `CAMCanvasInteraction.stepModelHandle`). Flat at z = 0,
    /// in the shapes' own frame like the rest of the overlay (`.faceOverlay`).
    static func renderObjects(forSTEPModelAt origin: SIMD2<Float>,
                              size: SIMD2<Float>,
                              boxColor: SIMD4<Float>,
                              handleColor: SIMD4<Float>) -> [RenderObject] {
        func point(_ x: Float, _ y: Float) -> SIMD3<Float> {
            SIMD3<Float>(x, y, 0)
        }

        let center = origin + size / 2
        let radius = Float(handleRadius)
        let cross = Float(handleCrossSize)

        var handle: [SIMD3<Float>] = []
        for i in 0..<handleSegments {
            let a0 = Float(i) / Float(handleSegments) * 2 * .pi
            let a1 = Float(i + 1) / Float(handleSegments) * 2 * .pi
            handle.append(point(center.x + radius * cos(a0), center.y + radius * sin(a0)))
            handle.append(point(center.x + radius * cos(a1), center.y + radius * sin(a1)))
        }
        handle.append(point(center.x - cross, center.y))
        handle.append(point(center.x + cross, center.y))
        handle.append(point(center.x, center.y - cross))
        handle.append(point(center.x, center.y + cross))

        let corners = [point(origin.x, origin.y), point(origin.x + size.x, origin.y),
                       point(origin.x + size.x, origin.y + size.y), point(origin.x, origin.y + size.y),
                       point(origin.x, origin.y)]

        // Handle first, like `renderObjects(for:)`: it should win where lines coincide
        return [RenderObject(role: .faceOverlay, points: handle, color: handleColor, primitive: .lineList),
                RenderObject(role: .faceOverlay, points: corners, color: boxColor,
                             primitive: .lineStrip, isDashed: true, dashLength: dashLength)]
    }

    private static func selectionBox(for object: D2_Object, color: SIMD4<Float>) -> RenderObject {
        let w = object.originalSize.width
        let h = object.originalSize.height
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: w, y: 0),
                       CGPoint(x: w, y: h), CGPoint(x: 0, y: h),
                       CGPoint(x: 0, y: 0)]
        return RenderObject(points: corners.map { simd(object.worldPoint(fromLocal: $0)) },
                            color: color,
                            primitive: .lineStrip,
                            isDashed: true,
                            dashLength: dashLength)
    }

    /// A ring plus a cross, as disconnected segments. Hairlines only, so no
    /// filled dot like the CoreAnimation one — QA item.
    private static func rotationHandle(for object: D2_Object, color: SIMD4<Float>) -> RenderObject {
        let cx = object.originalSize.width / 2
        let cy = object.originalSize.height / 2

        func local(_ dx: CGFloat, _ dy: CGFloat) -> SIMD3<Float> {
            simd(object.worldPoint(fromLocal: CGPoint(x: cx + dx, y: cy + dy)))
        }

        var points: [SIMD3<Float>] = []

        for i in 0..<handleSegments {
            let a0 = CGFloat(i) / CGFloat(handleSegments) * 2 * .pi
            let a1 = CGFloat(i + 1) / CGFloat(handleSegments) * 2 * .pi
            points.append(local(handleRadius * cos(a0), handleRadius * sin(a0)))
            points.append(local(handleRadius * cos(a1), handleRadius * sin(a1)))
        }

        points.append(local(-handleCrossSize, 0))
        points.append(local(handleCrossSize, 0))
        points.append(local(0, -handleCrossSize))
        points.append(local(0, handleCrossSize))

        return RenderObject(points: points, color: color, primitive: .lineList)
    }

    private static func simd(_ point: CGPoint) -> SIMD3<Float> {
        SIMD3<Float>(Float(point.x), Float(point.y), 0)
    }
}

/// What the toolpath scrubber puts on the canvas: the part of the toolpath cut
/// so far, and the cutter where it is.
enum CAMToolpathScrubOverlay {

    /// Same blue as every other toolpath on the canvas (`CAMSceneModel.Style.toolpathColor`).
    private static let pathColor = CAMSceneModel.Style.toolpathColor
    /// Same red as the controller's cutter.
    private static let markerColor = SIMD4<Float>(0.9, 0.1, 0.1, 1.0)
    private static let markerSegments = 32
    /// Lines running along the tool's surface (cone struts, dome arcs, tail lines), like the
    /// struts of the axes' arrowheads.
    private static let strutCount = 16
    private static let domeArcSteps = 12

    /// The whole toolpath; the scrubber narrows what is drawn with
    /// `visibleVertexCount`, so this is built once per generation.
    /// Role `.toolpathCutting` is how the scene's fast path finds it again.
    static func pathObject(for data: ToolpathScrubData) -> RenderObject {
        RenderObject(role: .toolpathCutting, points: data.points, color: pathColor, primitive: .lineList)
    }

    /// The cutter at `position` (its tip), as lines in the tool's shape, tip pointing down:
    ///
    /// - Flat cutters (end mill, corn, solder mask remover, drill, thread mill): a ring of the
    ///   tool's diameter at the tip's height, with spokes from its center.
    /// - Round bits (ball nose): a dome, a rim ring, rings of latitude and arcs down to the tip.
    /// - V-bits, chamfer and engraving bits: a cone, a rim ring, two rings between and struts
    ///   converging on the tip.
    ///
    /// Every one has a short tail, a cylinder of rings and lines going up from the rim.
    /// Role `.tool`, so the scene's fast path swaps it in place as the slider moves.
    static func marker(at position: SIMD3<Float>, tool: Tool) -> RenderObject {
        let diameter = Double(tool.toolDiameter)

        enum Tip {
            case flat
            case dome
            case cone(height: Float, topRadius: Float)
        }

        var tip = Tip.flat
        switch tool.type {
        case .ballNose:
            if diameter > 0 {
                tip = .dome
            }
        case .vBit, .chamfer, .engraving:
            if let cone = coneProfile(diameter: diameter,
                                      tipAngle: tool.tipAngle.map { Double($0) },
                                      length: tool.cuttingHeight.map { Double($0) }) {
                // The cone's own top radius, not the tool's: a flute shorter than the full cone
                // leaves it cut off short of the tool's diameter.
                tip = .cone(height: Float(cone.height), topRadius: Float(cone.height * tan(cone.halfAngle)))
            }
        case .endMill, .corn, .solderMaskRemover, .drill, .threadMill:
            break
        }

        // A hair-thin tool would vanish at any zoom
        let radius = max(Float(max(diameter, 0) / 2), 0.25)

        var points: [SIMD3<Float>] = []
        points.reserveCapacity(markerSegments * 12 + strutCount * 40)

        func point(_ r: Float, _ angle: Float, _ z: Float) -> SIMD3<Float> {
            SIMD3<Float>(position.x + r * cos(angle), position.y + r * sin(angle), position.z + z)
        }

        func line(_ a: SIMD3<Float>, _ b: SIMD3<Float>) {
            points.append(a)
            points.append(b)
        }

        func ring(radius r: Float, z: Float) {
            for i in 0..<markerSegments {
                let a0 = Float(i) / Float(markerSegments) * 2 * .pi
                let a1 = Float(i + 1) / Float(markerSegments) * 2 * .pi
                line(point(r, a0, z), point(r, a1, z))
            }
        }

        // The directions every spoke, arc and tail line runs along
        let angles: [Float] = (0..<strutCount).map { Float($0) / Float(strutCount) * 2 * .pi }

        var rimRadius = radius
        var rimZ: Float = 0

        switch tip {
        case .flat:
            for angle in angles {
                line(point(0, 0, 0), point(radius, angle, 0))
            }

        case .dome:
            rimZ = radius
            for phi in [Float.pi / 6, Float.pi / 3] {
                ring(radius: radius * sin(phi), z: radius - radius * cos(phi))
            }
            for angle in angles {
                var previous = point(0, angle, 0)
                for k in 1...domeArcSteps {
                    let phi = Float(k) / Float(domeArcSteps) * (.pi / 2)
                    let next = point(radius * sin(phi), angle, radius - radius * cos(phi))
                    line(previous, next)
                    previous = next
                }
            }

        case .cone(let height, let topRadius):
            rimRadius = topRadius
            rimZ = height
            let fractions: [Float] = [Float(1) / 3, 2 / 3]
            for fraction in fractions {
                ring(radius: topRadius * fraction, z: height * fraction)
            }
            for angle in angles {
                line(point(0, angle, 0), point(topRadius, angle, height))
            }
        }

        ring(radius: rimRadius, z: rimZ)

        // The tail: a bit of shank, in proportion to the tool
        let tailLength = max(rimRadius * 3, 2)
        ring(radius: rimRadius, z: rimZ + tailLength / 2)
        ring(radius: rimRadius, z: rimZ + tailLength)
        for angle in angles {
            line(point(rimRadius, angle, rimZ), point(rimRadius, angle, rimZ + tailLength))
        }

        return RenderObject(role: .tool, points: points, color: markerColor, primitive: .lineList)
    }

    /// A V-bit's cone: its half-angle (radians) and height (mm), from the tool's diameter, tip
    /// angle and cutting length. The angle and the diameter fix how tall the cone is
    /// (`radius / tan(half angle)`), so a missing length is worked out from them; a cutting
    /// length shorter than that cuts the cone off short of the full diameter. With no angle but
    /// a length, the angle is the one that takes the cone from a point to the full diameter in
    /// that length. `nil` when there is neither, or no diameter.
    static func coneProfile(diameter: Double, tipAngle: Double?, length: Double?) -> (halfAngle: Double, height: Double)? {
        let radius = diameter / 2
        guard radius > 0 else {
            return nil
        }
        let cuttingLength = length.flatMap { $0 > 0 ? $0 : nil }

        if let angle = tipAngle, angle > 0, angle < 180 {
            let halfAngle = angle / 2 * .pi / 180
            let fullHeight = radius / tan(halfAngle)
            return (halfAngle, cuttingLength.map { min($0, fullHeight) } ?? fullHeight)
        }
        if let cuttingLength {
            return (atan(radius / cuttingLength), cuttingLength)
        }
        return nil
    }
}
