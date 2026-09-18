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
                    // TODO(M3): confirm this against whatever front-facing
                    // winding the heightmap's pipeline state actually
                    // configures before turning on back-face culling — flip
                    // both triangles here if the mesh renders inside-out.
                    indices.append(v00); indices.append(v10); indices.append(v11)
                    indices.append(v00); indices.append(v11); indices.append(v01)
                }
            }
        }

        self.vertices = vertices
        self.indices = indices
    }
}
