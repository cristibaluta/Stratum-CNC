//
//  HeightmapMesh.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 18.09.2026.
//


//
//  HeightmapMesh.swift
//  Stratum CNC
//
//  Turns a `HeightmapGrid`'s height samples into an indexed triangle mesh.
//  Still pure Swift/simd — no `MTLDevice`, no GPU buffers. `MetalRenderer`
//  (M3) is the only thing that should ever turn this into something the GPU
//  can draw, same separation `RenderObject` already keeps for the wireframe
//  path.
//
//  One vertex per grid sample (not per cell corner) — the mesh is a "deformed
//  grid" in the sense the roadmap describes: `columns * rows` points, each
//  directly at a cell center, joined into `(columns - 1) * (rows - 1)` quads.
//  This is a simplification (a true corner-sampled grid would align exactly
//  with each cell's edges), but it halves the bookkeeping and is standard
//  for "quick preview" heightmap rendering — the difference is sub-cell and
//  not visible at any resolution coarse enough to be worth carving in real
//  time anyway.
//

import Foundation
import simd

struct HeightmapMesh {

    struct Vertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
    }

    /// Fresh on every `init` — lets `MetalCanvasView.Coordinator` (M4) tell
    /// "this is a genuinely new mesh, re-upload it" apart from "same mesh,
    /// SwiftUI just re-ran this view's body" without diffing
    /// `vertices`/`indices` (which, at real grid sizes, would cost more than
    /// the GPU upload it's trying to avoid).
    let id = UUID()

    /// Row-major, same order/count as `HeightmapGrid.heights`
    /// (`vertices[row * columns + col]`), so a future incremental update
    /// (M5) can touch just the vertices whose underlying cell changed
    /// without rebuilding the whole array.
    let vertices: [Vertex]

    /// Triangle list (3 indices per triangle), into `vertices`.
    let indices: [UInt32]

    /// Builds the mesh for a grid's *current* state — call again whenever
    /// the grid changes (a fresh carve, a scrub tick). Cheap relative to
    /// carving itself: this is one pass over the grid with only neighbor
    /// lookups, no toolpath traversal.
    init(grid: HeightmapGrid) {
        let columns = grid.columns
        let rows = grid.rows

        func clampedHeight(_ col: Int, _ row: Int) -> Float {
            let c = min(max(col, 0), columns - 1)
            let r = min(max(row, 0), rows - 1)
            return grid.heights[r * columns + c]
        }

        var vertices: [Vertex] = []
        vertices.reserveCapacity(columns * rows)

        for row in 0..<rows {
            for col in 0..<columns {
                let center = grid.center(col: col, row: row)
                let height = grid.heights[row * columns + col]

                // Central difference in each direction, clamped to the
                // grid's edge (mirrors the boundary value) rather than
                // wrapping or leaving a discontinuity at the border.
                let dx = (clampedHeight(col + 1, row) - clampedHeight(col - 1, row)) / (2 * grid.cellSize)
                let dy = (clampedHeight(col, row + 1) - clampedHeight(col, row - 1)) / (2 * grid.cellSize)

                // Surface normal for a height field z = f(x, y) is
                // (-df/dx, -df/dy, 1), normalized. Reads as "mostly up,"
                // tilting away from steep slopes — enough for flat lambertian
                // shading to make the carved shape legible.
                let normal = simd_normalize(SIMD3<Float>(-dx, -dy, 1))

                vertices.append(Vertex(position: SIMD3<Float>(center.x, center.y, height), normal: normal))
            }
        }

        var indices: [UInt32] = []
        if columns >= 2 && rows >= 2 {
            indices.reserveCapacity((columns - 1) * (rows - 1) * 6)

            for row in 0..<(rows - 1) {
                for col in 0..<(columns - 1) {
                    let v00 = UInt32(row * columns + col)
                    let v10 = UInt32(row * columns + col + 1)
                    let v01 = UInt32((row + 1) * columns + col)
                    let v11 = UInt32((row + 1) * columns + col + 1)

                    // Counter-clockwise as seen looking down -Z (standard
                    // math convention, matching the +Z-up normals above).
                    // Confirmed correct against `MetalRenderer`'s
                    // `.counterClockwise`/`.back` culling setup — the
                    // skirt/cap below reuse this exact convention rather
                    // than re-deriving it.
                    indices.append(v00); indices.append(v10); indices.append(v11)
                    indices.append(v00); indices.append(v11); indices.append(v01)
                }
            }
        }

        // Close the top surface into a solid-looking block: a vertical
        // skirt around the four sides (following the actual carved height
        // along each border row/column, so it meets the top surface with
        // no gap) down to `grid.bottomZ`, plus a flat bottom cap. Without
        // this the heightmap was just a floating sheet — correct depth-wise,
        // but with no visible thickness, which read as "wrong"/unfinished
        // even though the carve itself was fine.
        Self.appendSkirtAndBottomCap(grid: grid, vertices: &vertices, indices: &indices)

        self.vertices = vertices
        self.indices = indices
    }

    /// Appends the four vertical border walls and the bottom cap to
    /// `vertices`/`indices`, in place. Each wall vertex gets its own
    /// (duplicated) position rather than reusing a top-surface vertex,
    /// since its normal — horizontal, pointing away from the grid — is
    /// unrelated to the top surface's mostly-upward normal at that point.
    ///
    /// Winding: every triangle here is built as `(a, b, c)` where
    /// `cross(b - a, c - a)` points in the face's intended outward
    /// direction — the same right-hand-rule convention the top surface's
    /// `(v00, v10, v11)` ordering already follows (confirmed correct once
    /// the M4 tool-assignment gate was the actual reason nothing was
    /// drawing — see chat). No separate wind-order check needed here.
    private static func appendSkirtAndBottomCap(grid: HeightmapGrid, vertices: inout [Vertex], indices: inout [UInt32]) {
        let columns = grid.columns
        let rows = grid.rows
        let bottomZ = grid.bottomZ

        /// One border edge: `positions` walks it in the direction that
        /// keeps the grid's interior on the left (i.e. counter-clockwise
        /// around the perimeter, viewed from above) — south→east→north→west
        /// — and `outward` is that edge's constant horizontal outward
        /// normal.
        struct Edge {
            let positions: [(col: Int, row: Int)]
            let outward: SIMD3<Float>
        }
        let edges: [Edge] = [
            Edge(positions: (0..<columns).map { (col: $0, row: 0) }, outward: SIMD3<Float>(0, -1, 0)),                 // south, west→east
            Edge(positions: (0..<rows).map { (col: columns - 1, row: $0) }, outward: SIMD3<Float>(1, 0, 0)),           // east, south→north
            Edge(positions: (0..<columns).reversed().map { (col: $0, row: rows - 1) }, outward: SIMD3<Float>(0, 1, 0)), // north, east→west
            Edge(positions: (0..<rows).reversed().map { (col: 0, row: $0) }, outward: SIMD3<Float>(-1, 0, 0)),         // west, north→south
        ]

        for edge in edges {
            guard edge.positions.count >= 2 else { continue }
            for i in 0..<(edge.positions.count - 1) {
                let (col0, row0) = edge.positions[i]
                let (col1, row1) = edge.positions[i + 1]
                let p0 = grid.center(col: col0, row: row0)
                let p1 = grid.center(col: col1, row: row1)
                let h0 = grid.heights[row0 * columns + col0]
                let h1 = grid.heights[row1 * columns + col1]

                let top0 = SIMD3<Float>(p0.x, p0.y, h0)
                let top1 = SIMD3<Float>(p1.x, p1.y, h1)
                let bot0 = SIMD3<Float>(p0.x, p0.y, bottomZ)
                let bot1 = SIMD3<Float>(p1.x, p1.y, bottomZ)

                let base = UInt32(vertices.count)
                vertices.append(Vertex(position: top0, normal: edge.outward))
                vertices.append(Vertex(position: top1, normal: edge.outward))
                vertices.append(Vertex(position: bot0, normal: edge.outward))
                vertices.append(Vertex(position: bot1, normal: edge.outward))
                // (top0, bot0, top1) then (top1, bot0, bot1) — see winding note above.
                indices.append(base); indices.append(base + 2); indices.append(base + 1)
                indices.append(base + 1); indices.append(base + 2); indices.append(base + 3)
            }
        }

        // Bottom cap: a single flat rectangle spanning the grid's XY bounding
        // box, facing straight down. The grid itself is always an axis-
        // aligned rectangle (see `HeightmapGrid.init(stock:cellSize:)`'s note
        // on circular stock), so this always matches the carve's true extent.
        let minX = grid.originX
        let minY = grid.originY
        let maxX = grid.originX + Float(columns) * grid.cellSize
        let maxY = grid.originY + Float(rows) * grid.cellSize
        let down = SIMD3<Float>(0, 0, -1)

        let c00 = SIMD3<Float>(minX, minY, bottomZ)
        let c10 = SIMD3<Float>(maxX, minY, bottomZ)
        let c01 = SIMD3<Float>(minX, maxY, bottomZ)
        let c11 = SIMD3<Float>(maxX, maxY, bottomZ)

        let base = UInt32(vertices.count)
        vertices.append(Vertex(position: c00, normal: down))
        vertices.append(Vertex(position: c10, normal: down))
        vertices.append(Vertex(position: c01, normal: down))
        vertices.append(Vertex(position: c11, normal: down))
        // (c00, c01, c10) then (c10, c01, c11) — both outward/downward, see winding note above.
        indices.append(base); indices.append(base + 2); indices.append(base + 1)
        indices.append(base + 1); indices.append(base + 2); indices.append(base + 3)
    }
}
