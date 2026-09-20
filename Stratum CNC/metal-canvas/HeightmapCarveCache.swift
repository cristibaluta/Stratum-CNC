//
//  when.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.09.2026.
//


//
//  HeightmapCarveCache.swift
//  Stratum CNC
//
//  M6, step 1 of the scrub-performance roadmap: incremental carve with
//  checkpoints. Everywhere else in the heightmap pipeline still treats a
//  scrub position as "carve this whole prefix from scratch" — this is what
//  lets `CanvasSceneModel` stop doing that.
//

import Foundation
import simd

/// Caches a partially-carved `HeightmapGrid` plus periodic snapshots of its
/// heights, so moving to a new scrub position only has to carve the
/// segments between the last position and the new one, not redo the whole
/// prefix from segment zero.
///
/// Why this works: `HeightmapGrid.carve` only ever *lowers* a cell's height
/// (see its own doc comment) — a cell's final height is the minimum any
/// pass leaves it at. That means a grid already carved through segment i is
/// exactly the right starting point for carving segment i onward: nothing
/// needs undoing for a forward scrub, which is the common case while
/// dragging the slider right. A *backward* scrub does need undoing, though,
/// and there's no way to "uncarve" a cell once it's been lowered — the
/// height it had before simply isn't kept anywhere. Snapshots are the fix:
/// every `snapshotInterval` segments, a copy of `heights` is stashed, so
/// scrubbing back only has to replay forward from the nearest snapshot at
/// or before the new position, instead of from zero.
///
/// A pure value type on purpose: `CanvasSceneModel.carveMesh(for:)` runs on
/// a detached background task and hands the updated cache back to the main
/// actor when it's done (see `HeightmapRequest.cache`/
/// `finishHeightmapCarve`), the same way it already hands back a finished
/// `HeightmapMesh`. Because it's a value, a cancelled carve's in-progress
/// mutations just live in that task's own copy and vanish with it — the
/// cache last committed to `CanvasSceneModel` is never touched by a carve
/// that never finished.
struct HeightmapCarveCache {

    /// Everything that has to match between the cached grid and a new
    /// request for the cache to be reusable at all. A mismatch here — a
    /// different stock, tool, cell size, or XY offset — means the grid's
    /// shape, mask, or footprint math has changed, so there's no valid
    /// partial state to build on. The caller (`CanvasSceneModel.carveMesh`)
    /// starts a fresh cache instead; that's the same cost a full recarve
    /// always was, just for the (rare) case a checkpointed one can't help.
    struct Setup: Equatable {
        let originX: Float
        let originY: Float
        let cellSize: Float
        let columns: Int
        let rows: Int
        let topZ: Float
        let bottomZ: Float
        let mask: [Bool]?
        let tool: ToolSpec
        let offsetX: Float
        let offsetY: Float

        /// `grid` should be a freshly-built, uncarved grid (see
        /// `HeightmapGrid(stock:cellSize:)`) — only its shape fields are
        /// read, not its heights.
        init(grid: HeightmapGrid, tool: ToolSpec, offset: SIMD2<Float>) {
            originX = grid.originX
            originY = grid.originY
            cellSize = grid.cellSize
            columns = grid.columns
            rows = grid.rows
            topZ = grid.topZ
            bottomZ = grid.bottomZ
            mask = grid.mask
            self.tool = tool
            offsetX = offset.x
            offsetY = offset.y
        }
    }

    /// Cap on how many snapshots this cache keeps at once. Past that,
    /// `thinSnapshotsIfNeeded` halves the count (dropping every other one,
    /// keeping index 0 and the newest) and doubles `snapshotInterval` to
    /// match — so memory stays bounded on a huge file instead of growing
    /// with it, at the cost of a coarser fallback for scrubbing very far
    /// back. 64 snapshots at, say, 4 MB each (a 0.1 mm cell over a
    /// generously sized stock) is 256 MB worst case — comfortable headroom
    /// even on the smallest supported device, and normally far less: most
    /// stocks and most cell sizes produce a much smaller grid than that.
    private static let maxSnapshots = 64

    /// How many segments between snapshots. Doubles every time `snapshots`
    /// is thinned, so it stays in step with whichever snapshots survived.
    private var snapshotInterval: Int

    let setup: Setup

    /// The grid as carved through `carvedSegmentCount` segments of
    /// whichever prefix produced it.
    private(set) var grid: HeightmapGrid

    private(set) var carvedSegmentCount: Int

    /// Ascending by `segmentCount`. `[0]` is always the uncarved grid
    /// (segment count 0), kept permanently even once thinning starts — it's
    /// one extra array, and it means a scrub back to the very start never
    /// falls through to a full recarve no matter how much thinning has
    /// happened since.
    private var snapshots: [(segmentCount: Int, heights: [Float])]

    /// Starts a fresh cache from an uncarved `grid` — used the first time a
    /// scrub happens, or whenever a new request's `Setup` doesn't match an
    /// existing cache's (see `CanvasSceneModel.carveMesh`).
    init(setup: Setup, grid: HeightmapGrid, snapshotInterval: Int) {
        self.setup = setup
        self.grid = grid
        self.carvedSegmentCount = 0
        self.snapshotInterval = max(1, snapshotInterval)
        self.snapshots = [(0, grid.heights)]
    }

    /// Brings the cached grid to exactly `segments.count` segments carved —
    /// rewinding to the nearest snapshot first if that's earlier than
    /// what's already carved, then carving forward the rest. `segments` is
    /// always a prefix starting at segment zero (see
    /// `NCFileDocument.toolpathSegments(upTo:)`, the only producer of the
    /// slices this is called with), which is what makes "rewind, then
    /// replay forward" sufficient — there's no earlier starting point to
    /// worry about.
    ///
    /// Returns `nil` if the task carrying this out was cancelled partway —
    /// same contract `CanvasSceneModel.carveMesh`'s old whole-prefix carve
    /// had. The cache itself still reflects whatever forward progress was
    /// made before the cancellation was noticed; the caller keeps that (see
    /// `finishHeightmapCarve`) so the next attempt doesn't have to redo it.
    mutating func carve(through segments: ArraySlice<ToolpathSegment>) -> HeightmapGrid? {
        rewind(toAtMost: segments.count)
        guard carveForward(to: segments) else {
            return nil
        }
        return grid
    }

    /// Rewinds `grid` to the latest snapshot at or before `segmentCount`. A
    /// no-op when `segmentCount` is at or past what's already carved —
    /// that's a forward (or exact) scrub, which needs no rewind.
    private mutating func rewind(toAtMost segmentCount: Int) {
        guard segmentCount < carvedSegmentCount else {
            return
        }
        // `snapshots` is sorted ascending, so the last one at or before the
        // target is the closest one to replay forward from. `[0]` always
        // qualifies, so this never comes back empty.
        guard let index = snapshots.lastIndex(where: { $0.segmentCount <= segmentCount }) else {
            return
        }
        let snapshot = snapshots[index]
        grid.restoreHeights(snapshot.heights)
        carvedSegmentCount = snapshot.segmentCount

        // Drop any snapshots taken further along than the one just
        // restored to — they were for a scrub position we've now rewound
        // past. Left in place, carving forward again would eventually pass
        // that same segment count and append a *second* snapshot there
        // (see `carveForward`), breaking the ascending order this method
        // relies on to find the right snapshot next time.
        snapshots.removeLast(snapshots.count - index - 1)
    }

    /// Carves `segments[carvedSegmentCount..<segments.count]` onto `grid`,
    /// snapshotting every `snapshotInterval` segments as it goes. Checked
    /// for cancellation every 1024 segments, same cadence the old
    /// from-scratch carve used — frequent enough that a cancelled drag
    /// stops within a fraction of a second, cheap enough not to matter.
    private mutating func carveForward(to segments: ArraySlice<ToolpathSegment>) -> Bool {
        while carvedSegmentCount < segments.count {
            if (carvedSegmentCount & 0x3FF) == 0, Task.isCancelled {
                return false
            }

            let segment = segments[segments.index(segments.startIndex, offsetBy: carvedSegmentCount)]
            grid.carve(segment: segment, tool: setup.tool, offsetX: setup.offsetX, offsetY: setup.offsetY)
            carvedSegmentCount += 1

            if carvedSegmentCount % snapshotInterval == 0 {
                snapshots.append((carvedSegmentCount, grid.heights))
                thinSnapshotsIfNeeded()
            }
        }
        return true
    }

    /// Halves `snapshots` (keeping `[0]` and the newest) and doubles
    /// `snapshotInterval` once the count passes `maxSnapshots`. See
    /// `maxSnapshots`'s doc comment for why.
    private mutating func thinSnapshotsIfNeeded() {
        guard snapshots.count > Self.maxSnapshots else {
            return
        }
        var thinned: [(segmentCount: Int, heights: [Float])] = [snapshots[0]]
        // Start at 2, not 1, so `[0]` isn't immediately duplicated; end
        // before the last index so the newest snapshot (appended below) is
        // never dropped by the stride landing just short of it.
        var i = 2
        while i < snapshots.count - 1 {
            thinned.append(snapshots[i])
            i += 2
        }
        thinned.append(snapshots[snapshots.count - 1])
        snapshots = thinned
        snapshotInterval *= 2
    }
}