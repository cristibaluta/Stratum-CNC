//
//  StockPreviewView.swift
//  Stratum CNC
//
//  Renders a simple isometric preview of a StockMaterial, shaded
//  according to a texture inferred from the material's displayName
//  (metal / wood / plastic look). Works with the existing
//  StockMaterial / StockMaterialType / StockGeometry types.
//

import SwiftUI

// MARK: - Texture kind

/// Broad texture categories used purely for rendering.
/// Matched against `StockMaterialType.displayName` so this file
/// doesn't need to know your exact enum cases. Tweak the keyword
/// matching below if your material names differ.
enum StockTextureKind {
    case aluminum
    case steel
    case brass
    case wood
    case plastic
}

extension StockMaterialType {

    var stockTextureKind: StockTextureKind {
        let name = displayName.lowercased()

        if name.contains("wood") || name.contains("mdf") || name.contains("plywood") {
            return .wood
        }
        if name.contains("brass") || name.contains("bronze") || name.contains("copper") {
            return .brass
        }
        if name.contains("steel") || name.contains("iron") {
            return .steel
        }
        if name.contains("plastic") || name.contains("acetal") || name.contains("delrin")
            || name.contains("nylon") || name.contains("acrylic") || name.contains("hdpe")
            || name.contains("pvc") {
            return .plastic
        }
        return .aluminum
    }
}

private struct StockTexture {
    let light: Color
    let mid: Color
    let dark: Color
    let isMetallic: Bool
    let isWood: Bool
}

private extension StockTextureKind {

    var texture: StockTexture {
        switch self {
        case .aluminum:
            return StockTexture(
                light: Color(red: 0.86, green: 0.87, blue: 0.89),
                mid: Color(red: 0.72, green: 0.73, blue: 0.76),
                dark: Color(red: 0.46, green: 0.47, blue: 0.50),
                isMetallic: true, isWood: false
            )
        case .steel:
            return StockTexture(
                light: Color(red: 0.72, green: 0.74, blue: 0.77),
                mid: Color(red: 0.52, green: 0.54, blue: 0.57),
                dark: Color(red: 0.27, green: 0.29, blue: 0.32),
                isMetallic: true, isWood: false
            )
        case .brass:
            return StockTexture(
                light: Color(red: 0.95, green: 0.85, blue: 0.55),
                mid: Color(red: 0.80, green: 0.65, blue: 0.30),
                dark: Color(red: 0.52, green: 0.40, blue: 0.14),
                isMetallic: true, isWood: false
            )
        case .wood:
            return StockTexture(
                light: Color(red: 0.85, green: 0.68, blue: 0.46),
                mid: Color(red: 0.74, green: 0.56, blue: 0.35),
                dark: Color(red: 0.50, green: 0.35, blue: 0.20),
                isMetallic: false, isWood: true
            )
        case .plastic:
            return StockTexture(
                light: Color(red: 0.93, green: 0.93, blue: 0.95),
                mid: Color(red: 0.82, green: 0.82, blue: 0.85),
                dark: Color(red: 0.62, green: 0.62, blue: 0.66),
                isMetallic: false, isWood: false
            )
        }
    }
}

// MARK: - Isometric projection

private struct IsoProjector {
    var scale: CGFloat
    var origin: CGPoint

    /// x = right, y = up, z = towards viewer
    func project(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
        let angle = CGFloat.pi / 6 // 30°
        let fx = CGFloat(x), fy = CGFloat(y), fz = CGFloat(z)
        let px = (fx - fz) * cos(angle) * scale
        let py = ((fx + fz) * sin(angle) - fy) * scale
        return CGPoint(x: origin.x + px, y: origin.y + py)
    }
}

/// Projects a set of representative 3D points at scale 1 to work out
/// how much to scale + shift so the shape fits the canvas with padding.
private func fittedProjector(
    forPoints points: [(Double, Double, Double)],
    canvasSize: CGSize,
    padding: CGFloat
) -> IsoProjector {

    let probe = IsoProjector(scale: 1, origin: .zero)
    let projected = points.map { probe.project($0.0, $0.1, $0.2) }

    let minX = projected.map(\.x).min() ?? 0
    let maxX = projected.map(\.x).max() ?? 0
    let minY = projected.map(\.y).min() ?? 0
    let maxY = projected.map(\.y).max() ?? 0

    let w = max(maxX - minX, 1)
    let h = max(maxY - minY, 1)

    let availableW = max(canvasSize.width - padding * 2, 1)
    let availableH = max(canvasSize.height - padding * 2, 1)

    let scale = min(availableW / w, availableH / h)
    let centerX = (minX + maxX) / 2
    let centerY = (minY + maxY) / 2

    let origin = CGPoint(
        x: canvasSize.width / 2 - centerX * scale,
        y: canvasSize.height / 2 - centerY * scale
    )

    return IsoProjector(scale: scale, origin: origin)
}

// MARK: - Face decoration (wood grain / metallic sheen)

// One global light direction, isometric screen-space (unit-ish vector).
// Pick something pointing down-left, matching your top-lit look.
private let lightDir2D = CGVector(dx: -0.6, dy: -1)

private func decorate(face: Path, texture: StockTexture, in context: GraphicsContext, isLitFace: Bool) {
    var layer = context
    layer.clip(to: face)
    let bounds = face.boundingRect
    guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { return }

    if texture.isWood {
        // ... unchanged
    }

    if texture.isMetallic && isLitFace {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let len = max(bounds.width, bounds.height)
        let perp = CGVector(dx: -lightDir2D.dy, dy: lightDir2D.dx) // streak runs perpendicular to light
        let bandWidth: CGFloat = len * 0.12

        func offset(_ p: CGPoint, _ v: CGVector, _ s: CGFloat) -> CGPoint {
            CGPoint(x: p.x + v.dx * s, y: p.y + v.dy * s)
        }

        let a = offset(center, lightDir2D, -len)
        let b = offset(center, lightDir2D, len)

        var sheen = Path()
        sheen.move(to: offset(a, perp, -bandWidth))
        sheen.addLine(to: offset(a, perp, bandWidth))
        sheen.addLine(to: offset(b, perp, bandWidth))
        sheen.addLine(to: offset(b, perp, -bandWidth))
        sheen.closeSubpath()
        layer.fill(sheen, with: .color(.white.opacity(0.25)))
    }
}

// MARK: - Shape drawing

private func drawBox(
    width: Double, height: Double, depth: Double,
    texture: StockTexture, canvasSize: CGSize, padding: CGFloat,
    in context: GraphicsContext
) {
    // X = width (right), Y = depth/thickness (up), Z = height (into screen)
    let corners: [(Double, Double, Double)] = [
        (0, 0, 0), (width, 0, 0), (width, 0, height), (0, 0, height),
        (0, depth, 0), (width, depth, 0), (width, depth, height), (0, depth, height)
    ]
    let projector = fittedProjector(forPoints: corners, canvasSize: canvasSize, padding: padding)
    func p(_ i: Int) -> CGPoint { projector.project(corners[i].0, corners[i].1, corners[i].2) }

    var top = Path(); top.move(to: p(4)); top.addLine(to: p(5)); top.addLine(to: p(6)); top.addLine(to: p(7)); top.closeSubpath()
    var front = Path(); front.move(to: p(3)); front.addLine(to: p(2)); front.addLine(to: p(6)); front.addLine(to: p(7)); front.closeSubpath()
    var right = Path(); right.move(to: p(1)); right.addLine(to: p(2)); right.addLine(to: p(6)); right.addLine(to: p(5)); right.closeSubpath()

    context.fill(top, with: .linearGradient(Gradient(colors: [texture.light, texture.mid]), startPoint: p(7), endPoint: p(5)))
    context.fill(front, with: .color(texture.mid))
    context.fill(right, with: .color(texture.dark))

    decorate(face: top, texture: texture, in: context, isLitFace: true)
    decorate(face: front, texture: texture, in: context, isLitFace: true)
    decorate(face: right, texture: texture, in: context, isLitFace: false)

    let stroke = Color.black.opacity(0.25)
    [top, front, right].forEach { context.stroke($0, with: .color(stroke), lineWidth: 1) }
}

/// Shared cylinder-wall + top-cap drawing, used by both round bars and tubes.
private func cylinderPaths(
    radius: Double, length: Double, segments: Int, projector: IsoProjector
) -> (frontWall: [CGPoint], topRing: [CGPoint], bottomFrontArc: [CGPoint]) {

    func circlePoints(y: Double) -> [(Double, Double, Double)] {
        (0..<segments).map { i in
            // start at -45° so index 0..<segments/2 is exactly the front-facing half
            let theta = -Double.pi / 4 + 2 * Double.pi * Double(i) / Double(segments)
            return (radius * cos(theta), y, radius * sin(theta))
        }
    }

    let top3D = circlePoints(y: length)
    let bottom3D = circlePoints(y: 0)

    let topPts = top3D.map { projector.project($0.0, $0.1, $0.2) }
    let bottomPts = bottom3D.map { projector.project($0.0, $0.1, $0.2) }

    let half = segments / 2
    let frontTop = Array(topPts[0..<half])
    let frontBottom = Array(bottomPts[0..<half])

    return (frontTop, topPts, frontBottom)
}

private func drawCylinder(
    diameter: Double, length: Double,
    texture: StockTexture, canvasSize: CGSize, padding: CGFloat,
    in context: GraphicsContext
) {
    let r = diameter / 2
    let segments = 48

    let fitPoints: [(Double, Double, Double)] = [
        (r, 0, 0), (-r, 0, 0), (0, 0, r), (0, 0, -r),
        (r, length, 0), (-r, length, 0), (0, length, r), (0, length, -r)
    ]
    let projector = fittedProjector(forPoints: fitPoints, canvasSize: canvasSize, padding: padding)
    let (frontTop, topRing, frontBottom) = cylinderPaths(radius: r, length: length, segments: segments, projector: projector)

    // side wall: front bottom arc -> up -> front top arc reversed -> close
    var side = Path()
    side.move(to: frontBottom.first!)
    frontBottom.dropFirst().forEach { side.addLine(to: $0) }
    frontTop.reversed().forEach { side.addLine(to: $0) }
    side.closeSubpath()

    var top = Path()
    top.move(to: topRing.first!)
    topRing.dropFirst().forEach { top.addLine(to: $0) }
    top.closeSubpath()

    context.fill(side, with: .color(texture.mid))
    decorate(face: side, texture: texture, in: context, isLitFace: true)
    context.stroke(side, with: .color(.black.opacity(0.2)), lineWidth: 1)

    context.fill(top, with: .linearGradient(Gradient(colors: [texture.light, texture.mid]), startPoint: topRing[0], endPoint: topRing[topRing.count / 2]))
    decorate(face: top, texture: texture, in: context, isLitFace: true)
    context.stroke(top, with: .color(.black.opacity(0.25)), lineWidth: 1)

}

private func drawTube(
    outerDiameter: Double, innerDiameter: Double, length: Double,
    texture: StockTexture, canvasSize: CGSize, padding: CGFloat,
    in context: GraphicsContext
) {
    let rOuter = outerDiameter / 2
    let rInner = min(innerDiameter / 2, rOuter * 0.95)
    let segments = 48

    let fitPoints: [(Double, Double, Double)] = [
        (rOuter, 0, 0), (-rOuter, 0, 0), (0, 0, rOuter), (0, 0, -rOuter),
        (rOuter, length, 0), (-rOuter, length, 0), (0, length, rOuter), (0, length, -rOuter)
    ]
    let projector = fittedProjector(forPoints: fitPoints, canvasSize: canvasSize, padding: padding)

    let (frontTop, outerTopRing, frontBottom) = cylinderPaths(radius: rOuter, length: length, segments: segments, projector: projector)

    func ringPoints(radius: Double, y: Double) -> [CGPoint] {
        (0..<segments).map { i in
            let theta = 2 * Double.pi * Double(i) / Double(segments)
            return projector.project(radius * cos(theta), y, radius * sin(theta))
        }
    }
    let innerTopRing = ringPoints(radius: rInner, y: length)
    let innerBottomRing = ringPoints(radius: rInner, y: 0)
    let half = segments / 2
    let backTop = Array(innerTopRing[half..<segments])
    let backBottom = Array(innerBottomRing[half..<segments])

    // 1. Interior back wall of the bore — drawn FIRST, since it's the
    //    back-most visible surface. Anything that should occlude it
    //    (side wall, top annulus) gets painted over it below.
    var innerWall = Path()
    innerWall.move(to: backTop.first!)
    backTop.dropFirst().forEach { innerWall.addLine(to: $0) }
    backBottom.reversed().forEach { innerWall.addLine(to: $0) }
    innerWall.closeSubpath()

    context.fill(innerWall, with: .color(texture.dark.opacity(0.9)))
    context.stroke(innerWall, with: .color(.black.opacity(0.3)), lineWidth: 1)
    // deliberately no separate farBottomRim stroke — this path's own
    // boundary already includes that edge, and it'll be correctly
    // trimmed by whatever's painted over it next.

    // 2. Outer front wall
    var side = Path()
    side.move(to: frontBottom.first!)
    frontBottom.dropFirst().forEach { side.addLine(to: $0) }
    frontTop.reversed().forEach { side.addLine(to: $0) }
    side.closeSubpath()

    context.fill(side, with: .color(texture.mid))
    decorate(face: side, texture: texture, in: context, isLitFace: false)
    context.stroke(side, with: .color(.black.opacity(0.2)), lineWidth: 1)

    // 3. Top annulus — painted LAST. Its eoFill hole leaves the interior
    //    wall visible where the bore actually shows through, and its
    //    ring area correctly covers any part of innerWall/side that
    //    geometrically shouldn't be visible.
    var annulus = Path()
    annulus.move(to: outerTopRing.first!)
    outerTopRing.dropFirst().forEach { annulus.addLine(to: $0) }
    annulus.closeSubpath()
    annulus.move(to: innerTopRing.first!)
    innerTopRing.dropFirst().forEach { annulus.addLine(to: $0) }
    annulus.closeSubpath()

    context.fill(annulus, with: .color(texture.light), style: FillStyle(eoFill: true))
    decorate(face: annulus, texture: texture, in: context, isLitFace: true)
    context.stroke(annulus, with: .color(.black.opacity(0.25)), lineWidth: 1)
}

// MARK: - Public view

struct StockPreviewView: View {

    var geometry: StockGeometry
    var material: StockMaterialType

    var body: some View {
        Canvas { context, size in
            let texture = material.stockTextureKind.texture
            let padding = size.width * 0.05

            switch geometry {
            case .rectangular(let width, let height, let depth):
                drawBox(width: width,
                        height: height,
                        depth: depth,
                        texture: texture,
                        canvasSize: size,
                        padding: padding,
                        in: context)

            case .cylindrical(let diameter, let length):
                drawCylinder(diameter: diameter,
                             length: length,
                             texture: texture,
                             canvasSize: size,
                             padding: padding,
                             in: context)

            case .disk(let outerDiameter, let innerDiameter, let depth):
                drawTube(outerDiameter: outerDiameter,
                         innerDiameter: innerDiameter,
                         length: depth,
                         texture: texture,
                         canvasSize: size,
                         padding: padding,
                         in: context)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 16) {
            ForEach(Array(StockMaterialType.allCases.enumerated()), id: \.offset) { index, material in
                let sampleGeometry: StockGeometry = [
                    .rectangular(width: 100, height: 60, depth: 12),
                    .cylindrical(diameter: 30, length: 80),
                    .disk(outerDiameter: 40, innerDiameter: 20, depth: 60)
                ][index % 3]

                VStack(spacing: 6) {
                    StockPreviewView(geometry: sampleGeometry, material: material)
                        .frame(height: 140)
                    Text(material.displayName)
                        .font(.caption)
                }
            }
        }
        .padding()
    }
}
