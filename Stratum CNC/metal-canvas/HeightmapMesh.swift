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
//  is the only thing that should ever turn this into something the GPU can
//  draw, same separation `RenderObject` already keeps for the wireframe path.
//
//  Voxel-style ("pixel art") mesh: one flat quad per grid cell, at that
//  cell's own height, plus a vertical riser wall on any side where the
//  neighboring cell (or the grid's edge) sits lower — same idea as a
//  Minecraft-style heightfield. Deliberately *not* one shared vertex per
//  grid sample with averaged/interpolated normals (an earlier version of
//  this file did that) — sharing vertices across cells is exactly what
//  produces the smoothly blended, "softened" look; every face here gets
//  its own 4 vertices and its own constant normal, so cell boundaries stay
//  hard edges with no shading gradient smearing across them.
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

    /// No stable per-cell order to exploit here (unlike the old shared-grid
    /// layout) — every cell contributes a variable number of triangles
    /// (1 top face, 0–4 walls) depending on its neighbors, so this is just
    /// "however many triangles the carve happened to expose."
    let vertices: [Vertex]

    /// Triangle list (3 indices per triangle), into `vertices`.
    let indices: [UInt32]

    /// The stock's original top and bottom faces. The shader shades by how
    /// far below `topZ` a point sits, as a fraction of this range, so a
    /// carved floor reads as a different shade than the uncut top.
    let topZ: Float
    let bottomZ: Float

    /// Builds the mesh for a grid's *current* state — call again whenever
    /// the grid changes (a fresh carve, a scrub tick).
    init(grid: HeightmapGrid) {
        let columns = grid.columns
        let rows = grid.rows
        let cellSize = grid.cellSize
        let bottomZ = grid.bottomZ

        var vertices: [Vertex] = []
        var indices: [UInt32] = []
        // Rough capacity guess: 1 top quad + up to 4 wall quads per cell,
        // 4 verts / 6 indices per quad. Cheap insurance against repeated
        // array growth on a large grid; harmless if the guess is high.
        vertices.reserveCapacity(columns * rows * 4 * 5)
        indices.reserveCapacity(columns * rows * 6 * 5)

        /// Appends one flat quad (`a`, `b`, `c`, `d` in the same
        /// CCW-around-the-face order the wireframe/skirt code already
        /// established) with a single constant `normal` for all four
        /// corners — that's what keeps the face flat-shaded rather than
        /// blending into its neighbors.
        func appendQuad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, normal: SIMD3<Float>) {
            let base = UInt32(vertices.count)
            vertices.append(Vertex(position: a, normal: normal))
            vertices.append(Vertex(position: b, normal: normal))
            vertices.append(Vertex(position: c, normal: normal))
            vertices.append(Vertex(position: d, normal: normal))
            indices.append(base); indices.append(base + 1); indices.append(base + 2)
            indices.append(base); indices.append(base + 2); indices.append(base + 3)
        }

        // nil for rectangular stock (every cell is solid); see
        // `HeightmapGrid.mask`.
        let mask = grid.mask

        /// Height of the neighbor one cell over in `(dCol, dRow)`, or
        /// `bottomZ` if that neighbor is off the grid or not part of the
        /// stock (outside a round stock's circle, or in a disk's bore) — an
        /// out-of-bounds or empty neighbor reads as "open air all the way
        /// down," so the outline of the stock always gets a full-height
        /// wall, same as the old skirt.
        func neighborTop(col: Int, row: Int, dCol: Int, dRow: Int) -> Float {
            let nc = col + dCol, nr = row + dRow
            guard nc >= 0, nc < columns, nr >= 0, nr < rows else { return bottomZ }
            let neighborIndex = nr * columns + nc
            if let mask, !mask[neighborIndex] { return bottomZ }
            return grid.heights[neighborIndex]
        }

        for row in 0..<rows {
            for col in 0..<columns {
                // Cells with no stock draw nothing — no top face, and the
                // solid neighbors next to them already own the walls.
                if let mask, !mask[row * columns + col] { continue }

                let h = grid.heights[row * columns + col]
                let x0 = grid.originX + Float(col) * cellSize
                let x1 = x0 + cellSize
                let y0 = grid.originY + Float(row) * cellSize
                let y1 = y0 + cellSize

                let p00 = SIMD3<Float>(x0, y0, h)
                let p10 = SIMD3<Float>(x1, y0, h)
                let p11 = SIMD3<Float>(x1, y1, h)
                let p01 = SIMD3<Float>(x0, y1, h)

                // Top face: flat, dead level — a single (0, 0, 1) normal
                // for the whole cell instead of the old central-difference
                // slope estimate, which is exactly what was tilting/
                // blending each face into its neighbors.
                appendQuad(p00, p10, p11, p01, normal: SIMD3<Float>(0, 0, 1))

                // Riser walls: only where a neighbor (or the grid edge) is
                // actually lower than this cell — the taller cell always
                // owns the wall between it and a shorter neighbor, so each
                // internal step gets exactly one wall, not two coincident
                // ones. Same outward-normal/winding convention as the
                // skirt this replaces: `(top_a, bot_a, top_b)` then
                // `(top_b, bot_a, bot_b)` for an edge walked so that
                // `cross(down, along) == outward`.
                let south = neighborTop(col: col, row: row, dCol: 0, dRow: -1)
                if h > south {
                    appendQuad(SIMD3<Float>(x0, y0, h), SIMD3<Float>(x0, y0, south),
                              SIMD3<Float>(x1, y0, south), SIMD3<Float>(x1, y0, h),
                              normal: SIMD3<Float>(0, -1, 0))
                }
                let east = neighborTop(col: col, row: row, dCol: 1, dRow: 0)
                if h > east {
                    appendQuad(SIMD3<Float>(x1, y0, h), SIMD3<Float>(x1, y0, east),
                              SIMD3<Float>(x1, y1, east), SIMD3<Float>(x1, y1, h),
                              normal: SIMD3<Float>(1, 0, 0))
                }
                let north = neighborTop(col: col, row: row, dCol: 0, dRow: 1)
                if h > north {
                    appendQuad(SIMD3<Float>(x1, y1, h), SIMD3<Float>(x1, y1, north),
                              SIMD3<Float>(x0, y1, north), SIMD3<Float>(x0, y1, h),
                              normal: SIMD3<Float>(0, 1, 0))
                }
                let west = neighborTop(col: col, row: row, dCol: -1, dRow: 0)
                if h > west {
                    appendQuad(SIMD3<Float>(x0, y1, h), SIMD3<Float>(x0, y1, west),
                              SIMD3<Float>(x0, y0, west), SIMD3<Float>(x0, y0, h),
                              normal: SIMD3<Float>(-1, 0, 0))
                }
            }
        }

        // Bottom cap, facing straight down. Rectangular stock is a single
        // quad spanning the grid's whole XY bounding box. Round stock
        // follows its mask instead: one quad per horizontal run of solid
        // cells in each row, which traces the circle (and a disk's bore)
        // without a quad per cell.
        if let mask {
            for row in 0..<rows {
                let y0 = grid.originY + Float(row) * cellSize
                let y1 = y0 + cellSize
                var col = 0
                while col < columns {
                    guard mask[row * columns + col] else {
                        col += 1
                        continue
                    }
                    let runStart = col
                    while col < columns && mask[row * columns + col] {
                        col += 1
                    }
                    let x0 = grid.originX + Float(runStart) * cellSize
                    let x1 = grid.originX + Float(col) * cellSize
                    appendQuad(SIMD3<Float>(x0, y0, bottomZ), SIMD3<Float>(x0, y1, bottomZ),
                              SIMD3<Float>(x1, y1, bottomZ), SIMD3<Float>(x1, y0, bottomZ),
                              normal: SIMD3<Float>(0, 0, -1))
                }
            }
        } else {
            let minX = grid.originX
            let minY = grid.originY
            let maxX = grid.originX + Float(columns) * cellSize
            let maxY = grid.originY + Float(rows) * cellSize
            appendQuad(SIMD3<Float>(minX, minY, bottomZ), SIMD3<Float>(minX, maxY, bottomZ),
                      SIMD3<Float>(maxX, maxY, bottomZ), SIMD3<Float>(maxX, minY, bottomZ),
                      normal: SIMD3<Float>(0, 0, -1))
        }

        self.vertices = vertices
        self.indices = indices
        self.topZ = grid.topZ
        self.bottomZ = grid.bottomZ
    }
}
