//
//  OperationIcon3D.swift
//  Stratum CNC
//
//  The big icon of an operation in the operations picker: a block of stock in isometric view
//  with what the operation leaves in it (a pocket, a groove around a part, a stepped hole, a
//  thread, a bevelled edge...). The icon is a wireframe: visible edges are solid lines, hidden
//  edges are dotted, and only the surfaces the machine cuts are filled with the accent colour.
//  There is no background.
//
//  Drawn with a `Canvas` and no assets, so it follows light/dark mode and the accent colour.
//  The small icons (`OperationIcon`) stay SF Symbols: they are too small for a 3D drawing.
//
//  Geometry: x runs right-down on screen, y left-down, z up. The viewer sits at +x +y +z, so the
//  visible outer faces are the top, the y = W face (left) and the x = W face (right), and the
//  visible inner walls of a recess are the ones on its far side (x = min, y = min).
//

import SwiftUI
import StratumCAM

struct OperationIcon3D: View {
    let kind: SC.MachiningOperation.Kind
    var size: CGFloat = 56
    /// The icon of the operation that is chosen: the cut areas get a stronger accent colour.
    var isSelected = false

    var body: some View {
        Canvas { context, canvasSize in
            let iso = IsoScene(size: canvasSize, tintStrength: isSelected ? 1.0 : 0.8)
            iso.draw(kind, in: &context)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Scene

private struct P2 {
    var x: Double
    var y: Double
}

private struct V3 {
    var x: Double
    var y: Double
    var z: Double

    init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

private struct IsoScene {

    /// The stock block: W × W wide, T thick, top face at z = 0.
    private let W = 10.0
    private let T = 3.2

    private let origin: CGPoint
    private let scale: Double
    private let tintStrength: Double

    private let cos30 = 0.8660254

    init(size: CGSize, tintStrength: Double) {
        // The block spans 2·W·cos30 wide and W + T high on screen.
        let blockWidth = 2 * 10.0 * 0.8660254
        let blockHeight = 10.0 + 3.2
        let k = min(Double(size.width) / blockWidth, Double(size.height) / blockHeight) * 0.94
        self.scale = k
        self.origin = CGPoint(x: size.width / 2, y: (Double(size.height) - blockHeight * k) / 2)
        self.tintStrength = tintStrength
    }

    // MARK: Projection, colours and line styles

    private func point(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
        CGPoint(x: origin.x + (x - y) * cos30 * scale,
                y: origin.y + ((x + y) * 0.5 - z) * scale)
    }

    private func screen(_ p: P2, _ z: Double) -> CGPoint {
        point(p.x, p.y, z)
    }

    /// Line weight follows the size of the icon.
    private var lineWidth: CGFloat {
        CGFloat(scale * 0.3)
    }

    private var lineColor: Color {
        Color.primary.opacity(0.20)
    }

    private var hiddenColor: Color {
        Color.primary.opacity(0.05)
    }

    private var solidStyle: StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
    }

    private var hiddenStyle: StrokeStyle {
        StrokeStyle(lineWidth: lineWidth * 0.85, lineCap: .butt, lineJoin: .round,
                    dash: [lineWidth * 1.0, lineWidth * 1.9])
    }

    /// The fill of a cut surface. `amount` scales it (1 for a fully cut face).
    private func accentFill(_ amount: Double) -> Color {
        Color.accentColor.opacity(tintStrength * amount)
    }

    private func strokeSolid(_ ctx: inout GraphicsContext, _ path: Path) {
        ctx.stroke(path, with: .color(lineColor), style: solidStyle)
    }

    private func strokeHidden(_ ctx: inout GraphicsContext, _ path: Path) {
        ctx.stroke(path, with: .color(hiddenColor), style: hiddenStyle)
    }

    // MARK: Paths

    private func polygon(_ points: [V3]) -> Path {
        var path = Path()
        for (index, p) in points.enumerated() {
            let screen = point(p.x, p.y, p.z)
            if index == 0 {
                path.move(to: screen)
            } else {
                path.addLine(to: screen)
            }
        }
        path.closeSubpath()
        return path
    }

    private func polygon(_ points: [P2], z: Double) -> Path {
        polygon(points.map { V3($0.x, $0.y, z) })
    }

    /// Separate straight edges, each given by its two end points.
    private func segments(_ pairs: [(V3, V3)]) -> Path {
        var path = Path()
        for (a, b) in pairs {
            path.move(to: point(a.x, a.y, a.z))
            path.addLine(to: point(b.x, b.y, b.z))
        }
        return path
    }

    // MARK: Stock

    /// The three edges of the block that sit behind it.
    private var hiddenBlockEdges: [(V3, V3)] {
        [(V3(0, 0, 0), V3(0, 0, -T)),
         (V3(0, 0, -T), V3(W, 0, -T)),
         (V3(0, 0, -T), V3(0, W, -T))]
    }

    private func plainBlock(_ ctx: inout GraphicsContext) {
        strokeHidden(&ctx, segments(hiddenBlockEdges))
        strokeSolid(&ctx, segments([
            // top face
            (V3(0, 0, 0), V3(W, 0, 0)), (V3(W, 0, 0), V3(W, W, 0)),
            (V3(W, W, 0), V3(0, W, 0)), (V3(0, W, 0), V3(0, 0, 0)),
            // front corners and the bottom edges in front
            (V3(0, W, 0), V3(0, W, -T)), (V3(W, W, 0), V3(W, W, -T)), (V3(W, 0, 0), V3(W, 0, -T)),
            (V3(0, W, -T), V3(W, W, -T)), (V3(W, W, -T), V3(W, 0, -T))
        ]))
    }

    // MARK: Shapes in the XY plane

    private func roundedRect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double,
                             radius r: Double, segments n: Int = 6) -> [P2] {
        var points: [P2] = []
        let corners: [(Double, Double, Double)] = [(x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90),
                                                   (x0 + r, y0 + r, 180), (x1 - r, y0 + r, 270)]
        for (cx, cy, start) in corners {
            for i in 0...n {
                let angle = (start + 90 * Double(i) / Double(n)) * .pi / 180
                points.append(P2(x: cx + r * cos(angle), y: cy + r * sin(angle)))
            }
        }
        return points
    }

    private func circle(_ cx: Double, _ cy: Double, radius r: Double, segments n: Int = 40) -> [P2] {
        (0..<n).map { i in
            let angle = 2 * Double.pi * Double(i) / Double(n)
            return P2(x: cx + r * cos(angle), y: cy + r * sin(angle))
        }
    }

    /// A slot along x: two half circles joined.
    private func capsule(x0: Double, x1: Double, y: Double, radius r: Double) -> [P2] {
        var points: [P2] = []
        for i in 0...8 {
            let angle = (-90 + 180 * Double(i) / 8) * .pi / 180
            points.append(P2(x: x1 - r + r * cos(angle), y: y + r * sin(angle)))
        }
        for i in 0...8 {
            let angle = (90 + 180 * Double(i) / 8) * .pi / 180
            points.append(P2(x: x0 + r + r * cos(angle), y: y + r * sin(angle)))
        }
        return points
    }

    /// Positive for a counter-clockwise outline (x right, y up).
    private func signedArea(_ points: [P2]) -> Double {
        var area = 0.0
        for i in points.indices {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            area += a.x * b.y - b.x * a.y
        }
        return area
    }

    /// The unit normal of the edge a → b pointing out of the outline (`inward: false`) or into it.
    private func normal(from a: P2, to b: P2, ccw: Bool, inward: Bool) -> (x: Double, y: Double) {
        let dx = b.x - a.x
        let dy = b.y - a.y
        // For a CCW outline the left of the edge, (-dy, dx), points inward.
        var nx = ccw ? -dy : dy
        var ny = ccw ? dx : -dx
        if !inward {
            nx = -nx
            ny = -ny
        }
        let length = max((nx * nx + ny * ny).squareRoot(), 0.000001)
        return (nx / length, ny / length)
    }

    // MARK: Walls

    /// The lines of a wall that follows `outline` between two heights, seen from outside
    /// (`inward: false`, a part standing up) or from inside (`inward: true`, a recess).
    /// Only the walls facing the viewer are visible. Returns:
    /// - `solid`: the bottom edge and the vertical edges of the visible walls,
    /// - `hidden`: the same for the walls turned away (to be drawn dotted),
    /// - `faces`: the visible walls as one path, for filling.
    /// Vertical edges are drawn at corners and where the wall turns away from the viewer, so a
    /// curved wall gets its two outer lines and not one line per segment.
    private func wallPaths(_ outline: [P2], zTop: Double, zBottom: Double,
                           inward: Bool) -> (solid: Path, hidden: Path, faces: Path) {
        let n = outline.count
        let ccw = signedArea(outline) > 0
        let visible: [Bool] = (0..<n).map { i in
            let nrm = normal(from: outline[i], to: outline[(i + 1) % n], ccw: ccw, inward: inward)
            return nrm.x + nrm.y > 0.001
        }

        var solid = Path()
        var hidden = Path()
        var faces = Path()

        // Bottom edges, as runs so a dotted curve keeps one rhythm.
        var solidRun = false
        var hiddenRun = false
        for i in 0..<n {
            let a = screen(outline[i], zBottom)
            let b = screen(outline[(i + 1) % n], zBottom)
            if visible[i] {
                if !solidRun {
                    solid.move(to: a)
                    solidRun = true
                }
                solid.addLine(to: b)
                hiddenRun = false
            } else {
                if !hiddenRun {
                    hidden.move(to: a)
                    hiddenRun = true
                }
                hidden.addLine(to: b)
                solidRun = false
            }
        }

        // Visible wall faces.
        for i in 0..<n where visible[i] {
            let a = outline[i]
            let b = outline[(i + 1) % n]
            faces.move(to: screen(a, zTop))
            faces.addLine(to: screen(b, zTop))
            faces.addLine(to: screen(b, zBottom))
            faces.addLine(to: screen(a, zBottom))
            faces.closeSubpath()
        }

        // Vertical edges.
        for j in 0..<n {
            let prev = (j + n - 1) % n
            let next = (j + 1) % n
            let d1x = outline[j].x - outline[prev].x
            let d1y = outline[j].y - outline[prev].y
            let d2x = outline[next].x - outline[j].x
            let d2y = outline[next].y - outline[j].y
            let turn = abs(atan2(d1x * d2y - d1y * d2x, d1x * d2x + d1y * d2y))
            guard turn > 0.5 || visible[prev] != visible[j] else {
                continue
            }
            if visible[prev] || visible[j] {
                solid.move(to: screen(outline[j], zTop))
                solid.addLine(to: screen(outline[j], zBottom))
            } else {
                hidden.move(to: screen(outline[j], zTop))
                hidden.addLine(to: screen(outline[j], zBottom))
            }
        }

        return (solid, hidden, faces)
    }

    // MARK: Cuts

    /// A cut into the surface at `z0`, `depth` deep. Draws the floor and the far walls inside the
    /// opening (clipped to it) and the hidden edges dotted; `extra` draws on top of that, still
    /// clipped: a deeper step, a part standing in a groove, a thread.
    /// - `floorFill`, `wallFill`: how much of the accent colour the cut floor / far walls get (0 = none).
    /// - `floorHole`: an outline cut out of the floor fill, where a deeper cut continues.
    private func recess(_ ctx: inout GraphicsContext, _ opening: [P2], z0: Double = 0, depth: Double,
                        floorFill: Double = 1, wallFill: Double = 0, floorHole: [P2]? = nil,
                        ring: Bool = false,
                        extra: ((inout GraphicsContext) -> Void)? = nil) {
        let zFloor = z0 - depth
        let rim = polygon(opening, z: z0)
        let walls = wallPaths(opening, zTop: z0, zBottom: zFloor, inward: true)

        ctx.drawLayer { layer in
            layer.clip(to: rim)
            if floorFill > 0 {
                var floor = polygon(opening, z: zFloor)
                if let hole = floorHole {
                    floor.addPath(polygon(hole, z: zFloor))
                }
                layer.fill(floor, with: .color(accentFill(floorFill)), style: FillStyle(eoFill: true))
            }
            if wallFill > 0 {
                layer.fill(walls.faces, with: .color(accentFill(wallFill)))
            }
            layer.stroke(walls.solid, with: .color(lineColor), style: solidStyle)
            extra?(&layer)
        }

        ctx.stroke(walls.hidden, with: .color(hiddenColor), style: hiddenStyle)

        if ring {
            ctx.stroke(rim, with: .color(Color.accentColor),
                       style: StrokeStyle(lineWidth: lineWidth * 1.5, lineJoin: .round))
        } else {
            ctx.stroke(rim, with: .color(lineColor), style: solidStyle)
        }
    }

    // MARK: Operations

    func draw(_ kind: SC.MachiningOperation.Kind, in ctx: inout GraphicsContext) {
        switch kind {
            case .facing:      drawFacing(&ctx)
            case .chamfer:     drawChamfer(&ctx)
            case .pocket:
                plainBlock(&ctx)
                recess(&ctx, roundedRect(1.8, 2, 8.2, 8, radius: 1.0), depth: 1.6)
            case .pocket3D:
                plainBlock(&ctx)
                // Stepped floor: the deeper area follows what is left standing.
                let inner = roundedRect(3.2, 3.2, 6.8, 6.8, radius: 0.8)
                recess(&ctx, roundedRect(1.5, 1.5, 8.5, 8.5, radius: 1.2), depth: 1.0,
                       floorHole: inner) { layer in
                    recess(&layer, inner, z0: -1.0, depth: 1.5)
                }
            case .contour:
                drawContour(&ctx)
            case .slotting:
                plainBlock(&ctx)
                recess(&ctx, capsule(x0: 1.4, x1: 8.6, y: 5, radius: 0.9), depth: 1.4)
            case .engrave:
                drawEngrave(&ctx)
            case .drilling:
                plainBlock(&ctx)
                recess(&ctx, circle(5, 5, radius: 1.8), depth: T, floorFill: 0, wallFill: 0.5)
            case .counterbore:
                plainBlock(&ctx)
                let hole = circle(5, 5, radius: 1.6)
                recess(&ctx, circle(5, 5, radius: 3.3), depth: 1.0, floorHole: hole) { layer in
                    recess(&layer, hole, z0: -1.0, depth: 2.2, floorFill: 0, wallFill: 0.5)
                }
            case .boring:
                plainBlock(&ctx)
                // A finished bore: the wall is all machined and the rim is outlined.
                recess(&ctx, circle(5, 5, radius: 3.0), depth: T, floorFill: 0, wallFill: 1, ring: true)
            case .threadMilling:
                drawThread(&ctx)
        }
    }

    /// The top levelled over part of the block: a step, and the tool's passes on the lower side.
    private func drawFacing(_ ctx: inout GraphicsContext) {
        let h = 0.8
        let s = 3.5

        // The levelled surface is the cut face.
        ctx.fill(polygon([V3(0, s, -h), V3(W, s, -h), V3(W, W, -h), V3(0, W, -h)]),
                 with: .color(accentFill(1)))
        var passes = Path()
        for y in [5.0, 6.5, 8.0] {
            passes.move(to: point(0.4, y, -h))
            passes.addLine(to: point(W - 0.4, y, -h))
        }
        ctx.stroke(passes, with: .color(lineColor.opacity(0.4)),
                   style: StrokeStyle(lineWidth: lineWidth * 0.6, lineCap: .round))

        strokeHidden(&ctx, segments(hiddenBlockEdges))
        strokeSolid(&ctx, segments([
            // the higher top
            (V3(0, 0, 0), V3(W, 0, 0)), (V3(W, 0, 0), V3(W, s, 0)),
            (V3(W, s, 0), V3(0, s, 0)), (V3(0, s, 0), V3(0, 0, 0)),
            // the step
            (V3(0, s, 0), V3(0, s, -h)), (V3(W, s, 0), V3(W, s, -h)),
            // the lower top
            (V3(0, s, -h), V3(W, s, -h)), (V3(W, s, -h), V3(W, W, -h)),
            (V3(W, W, -h), V3(0, W, -h)), (V3(0, W, -h), V3(0, s, -h)),
            // the sides and the bottom in front
            (V3(0, W, -h), V3(0, W, -T)), (V3(W, W, -h), V3(W, W, -T)), (V3(W, 0, 0), V3(W, 0, -T)),
            (V3(0, W, -T), V3(W, W, -T)), (V3(W, W, -T), V3(W, 0, -T))
        ]))
    }

    /// A groove all round a part: the part is cut out of the stock.
    private func drawContour(_ ctx: inout GraphicsContext) {
        plainBlock(&ctx)
        let part = roundedRect(3.0, 3.0, 7.0, 7.0, radius: 1.2)
        let depth = 1.8
        recess(&ctx, roundedRect(1.2, 1.2, 8.8, 8.8, radius: 1.8), depth: depth,
               floorHole: part) { layer in
            let walls = wallPaths(part, zTop: 0, zBottom: -depth, inward: false)
            let top = polygon(part, z: 0)

            // The part stands in front of the far side of the groove: wipe that out.
            var silhouette = top
            silhouette.addPath(walls.faces)
            layer.blendMode = .clear
            layer.fill(silhouette, with: .color(Color.black))
            layer.blendMode = .normal

            layer.stroke(walls.hidden, with: .color(hiddenColor), style: hiddenStyle)
            layer.stroke(walls.solid, with: .color(lineColor), style: solidStyle)
            layer.stroke(top, with: .color(lineColor), style: solidStyle)
        }
    }

    /// A line cut shallow into the top.
    private func drawEngrave(_ ctx: inout GraphicsContext) {
        plainBlock(&ctx)
        var line = Path()
        for i in 0...40 {
            let u = Double(i) / 40
            let p = point(1.5 + 7 * u, 5 + 2.2 * sin(u * 2 * .pi * 1.1 + 0.4), 0)
            if i == 0 {
                line.move(to: p)
            } else {
                line.addLine(to: p)
            }
        }
        ctx.stroke(line, with: .color(accentFill(1.4)),
                   style: StrokeStyle(lineWidth: lineWidth * 1.8, lineCap: .round, lineJoin: .round))
    }

    /// A hole with the thread cut into its wall.
    private func drawThread(_ ctx: inout GraphicsContext) {
        plainBlock(&ctx)
        let r = 2.7
        recess(&ctx, circle(5, 5, radius: r), depth: 2.8) { layer in
            // Turns on the far half of the wall only (the near half faces away from the viewer).
            for turn in 0..<4 {
                let z = -0.5 - Double(turn) * 0.6
                var helix = Path()
                for i in 0...20 {
                    let t = Double(i) / 20
                    let angle = (135 + 180 * t) * .pi / 180
                    let p = point(5 + r * cos(angle), 5 + r * sin(angle), z - 0.25 * t)
                    if i == 0 {
                        helix.move(to: p)
                    } else {
                        helix.addLine(to: p)
                    }
                }
                layer.stroke(helix, with: .color(Color.accentColor),
                             style: StrokeStyle(lineWidth: lineWidth * 0.9, lineCap: .round))
            }
        }
    }

    /// A bevel along the two front top edges.
    private func drawChamfer(_ ctx: inout GraphicsContext) {
        let c = 0.9
        let right = [V3(W - c, 0, 0), V3(W - c, W - c, 0), V3(W, W - c, -c), V3(W, 0, -c)]
        let left = [V3(0, W - c, 0), V3(W - c, W - c, 0), V3(W - c, W, -c), V3(0, W, -c)]
        let corner = [V3(W - c, W - c, 0), V3(W, W - c, -c), V3(W, W, -c), V3(W - c, W, -c)]

        // The bevels are the cut faces, filled as one shape so there are no seams.
        var bevels = polygon(right)
        bevels.addPath(polygon(left))
        bevels.addPath(polygon(corner))
        ctx.fill(bevels, with: .color(accentFill(1)))

        strokeHidden(&ctx, segments(hiddenBlockEdges))
        strokeSolid(&ctx, segments([
            // the top
            (V3(0, 0, 0), V3(W - c, 0, 0)), (V3(W - c, 0, 0), V3(W - c, W - c, 0)),
            (V3(W - c, W - c, 0), V3(0, W - c, 0)), (V3(0, W - c, 0), V3(0, 0, 0)),
            // the bevels
            (V3(W - c, 0, 0), V3(W, 0, -c)), (V3(W, 0, -c), V3(W, W - c, -c)),
            (V3(W, W - c, -c), V3(W - c, W - c, 0)),
            (V3(0, W - c, 0), V3(0, W, -c)), (V3(0, W, -c), V3(W - c, W, -c)),
            (V3(W - c, W, -c), V3(W - c, W - c, 0)),
            (V3(W, W - c, -c), V3(W, W, -c)), (V3(W, W, -c), V3(W - c, W, -c)),
            // the sides and the bottom in front
            (V3(0, W, -c), V3(0, W, -T)), (V3(W, W, -c), V3(W, W, -T)), (V3(W, 0, -c), V3(W, 0, -T)),
            (V3(0, W, -T), V3(W, W, -T)), (V3(W, W, -T), V3(W, 0, -T))
        ]))
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(Array(SC.MachiningOperation.Kind.groups.enumerated()), id: \.offset) { _, group in
            HStack(spacing: 12) {
                ForEach(group) { kind in
                    OperationIcon3D(kind: kind, size: 56, isSelected: kind == .pocket)
                }
            }
        }
    }
    .padding()
}
