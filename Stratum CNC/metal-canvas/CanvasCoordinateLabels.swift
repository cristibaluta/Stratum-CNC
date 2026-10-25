//
//  CanvasCoordinateLabels.swift
//  Stratum CNC
//
//  The machine's coordinate system, drawn over the canvas as small pills
//  pinned to three points: home (0, 0) at the bed's top-right corner, the
//  bed's far corner at the bottom-left, and the inside corner of the
//  L-bracket with the anchor's real position. Each pill takes the color of
//  the object it belongs to (bed or anchor).
//
//  The Metal renderer has no text, so these are SwiftUI views placed through
//  the canvas's world → screen projection (`CanvasZoomModel`) and re-placed
//  after every frame, so they follow pan, zoom and orbit. They never take
//  clicks. The "Coordinates" entry in the objects list hides them all.
//

import SwiftUI
import Combine

struct CanvasCoordinateLabels: View {

    @ObservedObject var scene: CanvasSceneModel

    /// Bumped after each frame the canvas draws; reading it in `body` is
    /// what makes the pills follow the camera.
    @State private var frameTick = 0

    private struct Pill: Identifiable {
        let id: String
        /// Machine coordinates (mm) of the point the pill marks — the canvas
        /// is in machine coordinates, so this is also what the pill shows.
        let point: SIMD2<Float>
        let color: Color
        /// Which corner of the pill sits at the point; the pill extends away
        /// from it, back over the object it belongs to.
        let corner: Alignment
    }

    private var pills: [Pill] {
        let layout = scene.machineLayout
        let bed = CanvasLayer.workbed.tint ?? .gray
        let anchor = CanvasLayer.anchor.tint ?? .orange
        return [
            Pill(id: "home", point: layout.bedMax, color: bed, corner: .topTrailing),
            Pill(id: "far", point: layout.bedMin, color: bed, corner: .bottomLeading),
            Pill(id: "anchor", point: layout.activeAnchor, color: anchor, corner: .topTrailing)
        ]
    }

    var body: some View {
        GeometryReader { geo in
            let _ = frameTick
            ZStack(alignment: .topLeading) {
                if scene.isVisible(.coordinates) {
                    ForEach(pills) { pill in
                        let world = SIMD3<Float>(pill.point.x, pill.point.y, scene.fixtureZ)
                        if let p = scene.zoomModel.normalizedViewPoint(forWorld: world),
                           (-0.02...1.02).contains(p.x), (-0.02...1.02).contains(p.y) {
                            marker(pill)
                                .position(x: p.x * geo.size.width, y: p.y * geo.size.height)
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .allowsHitTesting(false)
        // Deferred a runloop turn: the canvas reports a frame from inside
        // SwiftUI's own update pass, where changing state is not allowed.
        .onReceive(scene.zoomModel.frameRendered.receive(on: DispatchQueue.main)) { _ in
            frameTick &+= 1
        }
    }

    /// A dot on the exact point, with the pill hanging off one corner of it.
    private func marker(_ pill: Pill) -> some View {
        let dx: CGFloat = pill.corner == .bottomLeading ? 6 : -6
        let dy: CGFloat = pill.corner == .bottomLeading ? -6 : 6
        return Circle()
            .fill(pill.color)
            .frame(width: 6, height: 6)
            .frame(width: 0, height: 0)
            .overlay(alignment: pill.corner) {
                Text(Self.text(for: pill.point))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(pill.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(pill.color, lineWidth: 1))
                    .fixedSize()
                    .offset(x: dx, y: dy)
            }
    }

    /// "-185, -185" — plain dot decimals whatever the Mac's locale, the way
    /// G-code and the machine write them.
    static func text(for machine: SIMD2<Float>) -> String {
        "\(number(machine.x)), \(number(machine.y))"
    }

    private static func number(_ value: Float) -> String {
        let v = Double(value)
        if v == 0 { return "0" }
        return v.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", v)
            : String(format: "%.2f", v)
    }
}
