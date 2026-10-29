//
//  EndMillGlyph.swift
//  Stratum CNC
//
//  The end mill drawing used wherever "the tools" are meant: the toolbar, the Tools Library
//  tile, the tool picker's library button and the End Mill type icon. Upright, tip down, so
//  it never needs rotating.
//

import SwiftUI

/// Side view of a flat end mill in the unit square, tip at the bottom: a shank, a shoulder, and
/// a wider fluted cutting body with a flat end. Stroke it for an outline icon; it follows the
/// foreground style it is given.
struct EndMillShape: Shape {

    func path(in rect: CGRect) -> Path {
        func pt(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }

        let shankLeft = 0.4, shankRight = 0.6
        let bodyLeft = 0.28, bodyRight = 0.72
        let top = 0.04, shoulder = 0.3, bottom = 0.96

        var p = Path()
        // Outline: shank, shoulder, body, flat end.
        p.move(to: pt(shankLeft, top))
        p.addLine(to: pt(shankLeft, shoulder - 0.04))
        p.addLine(to: pt(bodyLeft, shoulder + 0.04))
        p.addLine(to: pt(bodyLeft, bottom))
        p.addLine(to: pt(bodyRight, bottom))
        p.addLine(to: pt(bodyRight, shoulder + 0.04))
        p.addLine(to: pt(shankRight, shoulder - 0.04))
        p.addLine(to: pt(shankRight, top))
        p.closeSubpath()

        // Flutes: slanted cuts across the body.
        for y in [0.5, 0.67, 0.84] {
            p.move(to: pt(bodyLeft, y + 0.12))
            p.addLine(to: pt(bodyRight, y))
        }
        return p
    }
}

/// `EndMillShape` sized and weighted like an SF Symbol at `size` points; colour it with
/// `foregroundStyle`.
struct EndMillIcon: View {
    var size: CGFloat = 16

    var body: some View {
        EndMillShape()
            .stroke(style: StrokeStyle(lineWidth: max(1, size / 12), lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

/// Template `Image` of the end mill. Toolbars only tint image-backed icons, so a plain Shape
/// can render invisible there; this rasterizes it as a template image.
@MainActor
func endMillTemplateImage(size: CGFloat = 16) -> Image {
    let renderer = ImageRenderer(content: EndMillIcon(size: size).foregroundStyle(.black))
    renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
    guard let cg = renderer.cgImage else {
        return Image(systemName: "wrench.and.screwdriver")
    }
    let ns = NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    ns.isTemplate = true
    return Image(nsImage: ns)
}

#Preview {
    HStack(spacing: 20) {
        EndMillShape().stroke(lineWidth: 1.5).frame(width: 64, height: 64)
        EndMillIcon(size: 16)
    }
    .padding()
}
