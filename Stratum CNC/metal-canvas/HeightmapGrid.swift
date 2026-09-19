//
//  HeightmapGrid.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 18.09.2026.
//


//
//  HeightmapGrid.swift
//  Stratum CNC
//
//  The 2.5D stock preview described in the renderer roadmap: a grid over
//  X/Y where each cell stores the current top-Z of the stock. Carving a
//  toolpath segment only ever lowers cells, never raises them — there's no
//  way to represent material being added back, which is fine for milling.
//
//  Deliberately pure Swift / simd, no Metal types: this is CPU-side
//  simulation state. `metal-canvas/Heightmap/HeightmapMesh.swift` (M2) is
//  what turns a finished grid into triangles; `MetalRenderer` is the only
//  thing that turns *that* into GPU buffers. Same separation of concerns
//  `RenderObject` already keeps for the wireframe path.
//

import Foundation
import simd

struct HeightmapGrid {

    /// World-space X/Y of grid cell (0, 0)'s lower-left corner.
    let originX: Float
    let originY: Float
    let cellSize: Float
    let columns: Int
    let rows: Int

    /// The stock's fixed bottom face Z — never changes during a carve
    /// (only `heights`, the top face, does). `HeightmapMesh` uses this to
    /// close the surface into a solid-looking block (side walls + a bottom
    /// cap) instead of a floating sheet with no thickness.
    let bottomZ: Float

    /// The stock's original top face Z — where every cell starts. Together
    /// with `bottomZ` this is the full depth range `HeightmapMesh` hands to
    /// the shader, so it can shade a cell by how far down it was carved.
    let topZ: Float

    /// Row-major, `columns * rows` entries. `heights[row * columns + col]`
    /// is that column's current top-Z, starting at the stock's own top face
    /// and only ever decreasing as `carve` runs.
    private(set) var heights: [Float]

    /// Which cells actually contain stock, same row-major layout as
    /// `heights`. `nil` means every cell is solid — the case for
    /// rectangular stock, so it pays no memory or per-cell cost for this.
    /// Circular stock (`.cylindrical`/`.disk`) gets a mask: cells outside
    /// the outer circle (and inside a disk's bore) are empty, so they're
    /// never carved (see `carve`) and `HeightmapMesh` draws nothing for
    /// them, leaving the mesh round instead of the grid's bounding square.
    private(set) var mask: [Bool]?

    /// Builds an empty grid (every cell at `topZ`) covering `width` × `height`
    /// starting at `(originX, originY)`. `cellSize` is clamped away from
    /// zero/negative so a bad value can't produce an unusably huge (or
    /// infinite) grid. `bottomZ` defaults to 10mm below `topZ` for the
    /// handful of call sites (tests, previews) that don't care about a real
    /// stock thickness; `init(stock:cellSize:)` below always passes the
    /// material's actual depth.
    init(originX: Float, originY: Float, width: Float, height: Float, cellSize: Float, topZ: Float, bottomZ: Float? = nil) {
        self.originX = originX
        self.originY = originY
        self.cellSize = max(cellSize, 0.01)
        self.columns = max(1, Int((width / self.cellSize).rounded(.up)))
        self.rows = max(1, Int((height / self.cellSize).rounded(.up)))
        self.heights = [Float](repeating: topZ, count: columns * rows)
        self.bottomZ = bottomZ ?? (topZ - 10)
        self.topZ = topZ
    }

    /// Builds a grid sized to a `StockMaterial`'s own bounding box, mirroring
    /// the coordinate convention `RenderObject.stockBox(for:)` already uses
    /// (stock's XY extent starts at the origin).
    ///
    /// Circular stock (`.cylindrical`/`.disk`) still gets the enclosing
    /// square as its grid, but with a mask (see `mask`) that marks only the
    /// cells inside the circle — and outside a disk's bore — as stock. The
    /// circle is centered at `(radius, radius)`, same as the wireframe
    /// stock (`RenderObject.stockCylinder`/`stockDisk`) and the 2D
    /// `StockLayer`.
    init(stock: StockMaterial, cellSize: Float) {
        switch stock.geometry {
            case let .rectangular(width, height, depth):
                self.init(originX: 0, originY: 0,
                          width: Float(width), height: Float(height),
                          cellSize: cellSize, topZ: 0, bottomZ: -Float(depth))

            case let .cylindrical(diameter, length):
                let d = Float(diameter)
                self.init(originX: 0, originY: 0, width: d, height: d,
                          cellSize: cellSize, topZ: 0, bottomZ: -Float(length))
                applyRingMask(outerRadius: d / 2, innerRadius: 0)

            case let .disk(outerDiameter, innerDiameter, depth):
                let d = Float(outerDiameter)
                self.init(originX: 0, originY: 0, width: d, height: d,
                          cellSize: cellSize, topZ: 0, bottomZ: -Float(depth))
                // Same clamp `RenderObject.stockDisk` applies to the bore.
                applyRingMask(outerRadius: d / 2,
                              innerRadius: max(0, min(Float(innerDiameter), d)) / 2)
        }
    }

    /// Marks a cell as stock only if its center lies within `outerRadius`
    /// of the grid's circle center and at least `innerRadius` away from it.
    /// `innerRadius == 0` is a plain solid circle.
    private mutating func applyRingMask(outerRadius: Float, innerRadius: Float) {
        let centerX = originX + outerRadius
        let centerY = originY + outerRadius
        let outerSquared = outerRadius * outerRadius
        let innerSquared = innerRadius * innerRadius

        var mask = [Bool](repeating: false, count: columns * rows)
        for row in 0..<rows {
            for col in 0..<columns {
                let cellCenter = center(col: col, row: row)
                let dx = cellCenter.x - centerX
                let dy = cellCenter.y - centerY
                let distanceSquared = dx * dx + dy * dy
                mask[row * columns + col] = distanceSquared <= outerSquared
                    && (innerRadius <= 0 || distanceSquared >= innerSquared)
            }
        }
        self.mask = mask
    }

    // MARK: Indexing

    private func columnRow(forX x: Float, y: Float) -> (col: Int, row: Int) {
        let col = Int(((x - originX) / cellSize).rounded(.down))
        let row = Int(((y - originY) / cellSize).rounded(.down))
        return (col, row)
    }

    private func index(col: Int, row: Int) -> Int? {
        guard col >= 0, col < columns, row >= 0, row < rows else { return nil }
        return row * columns + col
    }

    /// World-space X/Y of a cell's center — used both for carving (measuring
    /// a cell's offset from the tool centerline) and, later, for mesh
    /// generation (M2).
    func center(col: Int, row: Int) -> SIMD2<Float> {
        SIMD2<Float>(originX + (Float(col) + 0.5) * cellSize,
                     originY + (Float(row) + 0.5) * cellSize)
    }

    subscript(col: Int, row: Int) -> Float? {
        index(col: col, row: row).map { heights[$0] }
    }

    // MARK: Carving

    /// Lowers every cell a tool's footprint overlaps as it sweeps from
    /// `segment.start` to `segment.end`. Call once per segment, in toolpath
    /// order. A cell's final height only depends on the *minimum* Z any
    /// pass leaves it at, so a grid can equally well be carved fresh up to
    /// any prefix of a file — that's how the scrubber will drive this once
    /// it's wired in (see the roadmap's M5 note).
    mutating func carve(segment: ToolpathSegment, tool: ToolSpec, offsetX: Float = 0, offsetY: Float = 0) {
        // Rapids don't cut. Every tessellated arc segment carries only the
        // `.arc` flag (see `GCodeParser.appendArc`), not `.cutting`, so both
        // need checking here.
        let cuts = segment.flags & ToolpathFlags.cutting != 0 || segment.flags & ToolpathFlags.arc != 0
        guard cuts else { return }

        // `xyOffset`, applied once here rather than per-cell-sample below:
        // translating the segment's own endpoints before the bbox/loop is
        // exactly equivalent to shifting every sampled `cellCenter` by the
        // same amount (it's a rigid translation), but cheaper — one add
        // instead of one per cell — and it keeps the bounding-box math
        // below correct for free, instead of needing its own separate
        // widening by the offset.
        let offset2D = SIMD2<Float>(offsetX, offsetY)
        let start2D = SIMD2<Float>(segment.start.x, segment.start.y) + offset2D
        let end2D = SIMD2<Float>(segment.end.x, segment.end.y) + offset2D
        let travel = end2D - start2D
        let travelLengthSquared = simd_length_squared(travel)

        let radius = ToolFootprint.radius(for: tool)
        guard radius > 0 else { return }

        // Bounding box of the swept footprint, clamped to the grid, so only
        // cells that could possibly be under the tool get visited.
        let minX = min(start2D.x, end2D.x) - radius
        let maxX = max(start2D.x, end2D.x) + radius
        let minY = min(start2D.y, end2D.y) - radius
        let maxY = max(start2D.y, end2D.y) + radius

        let (colStart, rowStart) = columnRow(forX: minX, y: minY)
        let (colEnd, rowEnd) = columnRow(forX: maxX, y: maxY)

        let firstCol = max(0, colStart)
        let lastCol = min(columns - 1, colEnd)
        let firstRow = max(0, rowStart)
        let lastRow = min(rows - 1, rowEnd)
        guard firstCol <= lastCol, firstRow <= lastRow else { return }

        for row in firstRow...lastRow {
            for col in firstCol...lastCol {
                // Empty cells (outside a round stock, or in a disk's bore)
                // have nothing to cut.
                if let mask, !mask[row * columns + col] { continue }

                let cellCenter = center(col: col, row: row)

                // Closest point on the segment to this cell's center — the
                // standard point-to-segment projection, clamped to the
                // segment's ends — and how far along the segment (0...1)
                // that point sits, so the tip's Z can be interpolated there.
                let t: Float
                if travelLengthSquared > 0 {
                    let raw = simd_dot(cellCenter - start2D, travel) / travelLengthSquared
                    t = min(max(raw, 0), 1)
                } else {
                    t = 0 // zero-length segment; the parser filters these out before they get here
                }
                let closestPoint = start2D + travel * t
                let offset = simd_distance(cellCenter, closestPoint)

                guard offset <= radius else { continue }

                let tipZ = segment.start.z + (segment.end.z - segment.start.z) * t
                guard let surfaceZ = ToolFootprint.surfaceZ(for: tool, tipZ: tipZ, radialOffset: offset) else {
                    continue
                }

                let idx = row * columns + col
                heights[idx] = min(heights[idx], surfaceZ)
            }
        }
    }

    /// Carves a whole run of segments — a full toolpath, or a prefix of one
    /// for the scrubber — with a single active tool.
    ///
    /// Multi-tool files (a program with more than one `T` change) need a
    /// per-segment tool lookup instead of one fixed `tool`; that's the M6
    /// follow-up once tool-number → `ToolSpec` assignment exists somewhere
    /// callable from here (today it's only wired up as far as
    /// `CanvasSceneModel.toolDiameter`/`toolLength`, which assumes a single
    /// active tool, same as this method does).
    mutating func carve(segments: some Sequence<ToolpathSegment>, tool: ToolSpec, offsetX: Float = 0, offsetY: Float = 0) {
        for segment in segments {
            carve(segment: segment, tool: tool, offsetX: offsetX, offsetY: offsetY)
        }
    }
}
