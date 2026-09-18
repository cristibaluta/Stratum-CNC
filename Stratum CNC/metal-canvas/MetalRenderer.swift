//
//  RenderVertex.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 16.09.2026.
//

import Foundation
import MetalKit
import simd

struct RenderVertex {
    var position: SIMD3<Float>
    var color: SIMD4<Float>
    var dist: Float // Distance along path
}

/// GPU-backed draw call. Holds a live `MTLBuffer`, so it can only be built
/// where a `MTLDevice` is available — that's `MetalRenderer`, and nowhere else.
/// The model layer never sees this type; it only ever hands over `RenderObject`.
private struct RenderBatch {
    var vertexBuffer: MTLBuffer
    /// Total vertices actually in `vertexBuffer`.
    var vertexCount: Int
    /// How many of those vertices to draw this frame — `<= vertexCount`.
    /// Separate from `vertexCount` so the scrubber can shrink/grow what's
    /// drawn (`RenderObject.visibleVertexCount`) without touching the
    /// buffer: see `updateGeometry`.
    var drawVertexCount: Int
    var primitiveType: MTLPrimitiveType
    var role: RenderRole? = nil
    var isDashed: Bool = false
    var dashLength: Float = 5.0
    /// Depth-only face geometry for this batch's solid, if it has one (see
    /// `RenderObject.occluderFaces`). Drawn in `draw(in:)` pass 0, before
    /// any edges, so the edge passes have real surface depth to test against.
    var occluderBuffer: MTLBuffer?
    var occluderVertexCount: Int = 0
}

private extension RenderPrimitive {
    var mtlPrimitiveType: MTLPrimitiveType {
        switch self {
            case .lineStrip: return .lineStrip
            case .lineList: return .line
        }
    }
}

/// The rendering pipeline:
/// 1. Device — the GPU itself
/// 2. Command Queue — the pipeline of work
/// 3. Command Buffer — one frame's worth of instructions
/// 4. Render Pass Descriptor + Encoder — the actual draw commands
/// 5. Pipeline State — the compiled shaders
/// 6. Submit and present
///Get a drawable (the texture you'll draw into, usually from MTKView or CAMetalLayer)
///Make a command buffer from the queue
///Make a render command encoder with a render pass descriptor pointing at that drawable
///Set pipeline state, bind buffers/textures, issue draw calls
///End encoding
///Present the drawable and commit the command buffer

@MainActor
class MetalRenderer: NSObject {

    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    /// Same shaders as `pipelineState`, but with color writes disabled.
    /// Used for the occluder-face pre-pass — it needs to affect the depth
    /// buffer only, never what's actually on screen.
    private var depthOnlyPipelineState: MTLRenderPipelineState!

    // Depth states for the two-pass hidden-line render (see `draw(in:)`):
    // `depthStateVisible` is the normal pass, `depthStateHidden` is the
    // second pass that picks up everything the first pass occluded.
    private var depthStateVisible: MTLDepthStencilState!
    private var depthStateHidden: MTLDepthStencilState!

    /// Turn the second pass on/off. When off, occluded geometry simply
    /// isn't drawn (the old behavior).
    var showHiddenLines: Bool = true
    /// Dash length used for hidden portions of a line that isn't already
    /// dashed itself. Lines that already have their own `isDashed` pattern
    /// keep that pattern when hidden.
    private let hiddenLineDashLength: Float = 1.0

    /// Depth bias applied only while drawing occluder faces (pass 0), so an
    /// edge sitting exactly on its own solid's surface reliably wins the
    /// depth test against that surface instead of z-fighting with it.
    /// Empirical — nudge these if edges flicker or a solid's own outline
    /// starts vanishing at certain angles.
    private let occluderDepthBias: Float = 2.0
    private let occluderDepthBiasSlope: Float = 2.0

    var camera = Camera()
    private var renderBatches: [RenderBatch] = []

    // Kept around only so we can compute a bounding sphere for the initial
    // "fit to screen" — the GPU buffers built into `renderBatches` don't carry
    // positions in a form that's cheap to read back.
    private var lastObjects: [RenderObject] = []
    private var hasFittedInitialContent = false

    /// Last built batch per `RenderObject.id`, so `updateGeometry` can tell
    /// "this is the same object, just with a different `visibleVertexCount`"
    /// (reuse the buffer) apart from "this is genuinely new geometry"
    /// (rebuild it). Safe to key on `id` alone: `RenderObject` vends a fresh
    /// UUID every time one is constructed, so the id can only stay the same
    /// across two `updateGeometry` calls if the same struct instance —
    /// mutated in place, e.g. via `settingVisibleVertexCount` — was reused,
    /// never if the geometry was rebuilt from scratch.
    private var batchesByID: [UUID: RenderBatch] = [:]

    init?(metalView: MTKView) {
        super.init()
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            return nil
        }
        self.device = defaultDevice
        metalView.device = defaultDevice
        metalView.clearColor = MTLClearColor(red: 0.1, green: 0.11, blue: 0.13, alpha: 1.0)
        metalView.depthStencilPixelFormat = .depth32Float

        self.commandQueue = device.makeCommandQueue()

        setupPipeline(metalView: metalView)
        setupDepthStates()

        renderBatches = [buildRenderBatch(from: .stockBox())].compactMap { $0 }
    }

    /// The only place a `RenderObject` gets turned into a GPU-backed `RenderBatch`.
    private func buildRenderBatch(from object: RenderObject) -> RenderBatch? {
        let vertices = buildVertices(for: object)
        guard !vertices.isEmpty,
              let buffer = device.makeBuffer(bytes: vertices,
                                             length: vertices.count * MemoryLayout<RenderVertex>.stride,
                                             options: .storageModeShared) else {
            return nil
        }

        // Occluder faces don't need real color/dist — nothing ever reads them
        // (the depth-only pipeline writes no color, and `dashLength` is
        // forced to 0 for this pass so the fragment shader never discards).
        // They're just packed into the same `RenderVertex` layout so both
        // passes can share one vertex descriptor/shader pair.
        var occluderBuffer: MTLBuffer?
        if !object.occluderFaces.isEmpty {
            let occluderVertices = object.occluderFaces.map {
                RenderVertex(position: $0, color: SIMD4<Float>(repeating: 0), dist: 0)
            }
            occluderBuffer = device.makeBuffer(bytes: occluderVertices,
                                               length: occluderVertices.count * MemoryLayout<RenderVertex>.stride,
                                               options: .storageModeShared)
        }

        return RenderBatch(vertexBuffer: buffer,
                           vertexCount: vertices.count,
                           drawVertexCount: object.visibleVertexCount.map { min($0, vertices.count) } ?? vertices.count,
                           primitiveType: object.primitive.mtlPrimitiveType,
                           role: object.role,
                           isDashed: object.isDashed,
                           dashLength: object.dashLength,
                           occluderBuffer: occluderBuffer,
                           occluderVertexCount: object.occluderFaces.count)
    }

    /// Expands a `RenderObject`'s points into GPU vertices, accumulating
    /// distance-along-path as we go (used for dashing in the fragment shader).
    private func buildVertices(for object: RenderObject) -> [RenderVertex] {
        var vertices: [RenderVertex] = []
        vertices.reserveCapacity(object.points.count)
        var totalDistance: Float = 0
        for (i, point) in object.points.enumerated() {
            if i > 0 {
                totalDistance += simd_distance(point, object.points[i - 1])
            }
            vertices.append(RenderVertex(position: point, color: object.color, dist: totalDistance))
        }
        return vertices
    }

    private func setupPipeline(metalView: MTKView) {

        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "vertex_main"),
              let fragmentFunction = library.makeFunction(name: "fragment_main") else {
            print("❌ Error: Could not find shader functions.")
            return
        }

        let vertexDescriptor = MTLVertexDescriptor()
        // Position
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        // Color
        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0

        // Distance attribute for dashed lines
        vertexDescriptor.attributes[2].format = .float
        vertexDescriptor.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride + MemoryLayout<SIMD4<Float>>.stride
        vertexDescriptor.attributes[2].bufferIndex = 0

        vertexDescriptor.layouts[0].stride = MemoryLayout<RenderVertex>.stride

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        pipelineDescriptor.vertexDescriptor = vertexDescriptor

        pipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor)

        // Depth-only variant for the occluder-face pre-pass: same shaders,
        // same vertex layout, but no color writes — it exists purely to
        // stamp solid-surface depth into the depth buffer before any edges
        // are drawn (see `RenderObject.occluderFaces` and `draw(in:)` pass 0).
        let depthOnlyDescriptor = MTLRenderPipelineDescriptor()
        depthOnlyDescriptor.vertexFunction = vertexFunction
        depthOnlyDescriptor.fragmentFunction = fragmentFunction
        depthOnlyDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        depthOnlyDescriptor.colorAttachments[0].writeMask = []
        depthOnlyDescriptor.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        depthOnlyDescriptor.vertexDescriptor = vertexDescriptor

        depthOnlyPipelineState = try? device.makeRenderPipelineState(descriptor: depthOnlyDescriptor)
    }

    /// Two depth-stencil states, one per pass of the hidden-line render:
    /// - `depthStateVisible`: ordinary depth test (`.less`), writes depth.
    ///   Whatever's actually in front ends up in the depth buffer.
    /// - `depthStateHidden`: inverted test (`.greater`), no depth write.
    ///   A fragment only survives this pass if it's *farther* from the
    ///   camera than what pass one already put in the depth buffer at that
    ///   pixel — i.e. exactly the parts of the geometry that are occluded.
    ///   Not writing depth here means this pass can't occlude itself or
    ///   later batches, and an exact tie (a line's hidden pass falling on
    ///   its own already-drawn pixels) fails `.greater`, so it doesn't
    ///   double-draw on top of the solid pass.
    private func setupDepthStates() {
        let visibleDescriptor = MTLDepthStencilDescriptor()
        visibleDescriptor.depthCompareFunction = .less
        visibleDescriptor.isDepthWriteEnabled = true
        depthStateVisible = device.makeDepthStencilState(descriptor: visibleDescriptor)

        let hiddenDescriptor = MTLDepthStencilDescriptor()
        hiddenDescriptor.depthCompareFunction = .greater
        hiddenDescriptor.isDepthWriteEnabled = false
        depthStateHidden = device.makeDepthStencilState(descriptor: hiddenDescriptor)
    }

    /// Sync GPU state from the model's plain-data description of what to
    /// draw. This is the seam: everything upstream of here (model, views)
    /// only ever deals with `RenderObject`; only this call touches
    /// `device.makeBuffer`. It only *rebuilds* a buffer for genuinely new
    /// geometry, though — see `batchesByID` — so calling this on every
    /// scrub tick is fine.
    func updateGeometry(objects: [RenderObject]) {
        lastObjects = objects

        var updated: [RenderBatch] = []
        updated.reserveCapacity(objects.count)
        var keepIDs = Set<UUID>()
        keepIDs.reserveCapacity(objects.count)

        for object in objects {
            keepIDs.insert(object.id)

            if var batch = batchesByID[object.id] {
                // Same identity as last time this ran — the geometry that
                // produced `batch.vertexBuffer` hasn't changed (see the
                // `batchesByID` doc comment), so reuse the buffer as-is and
                // only update how much of it gets drawn. This is the path
                // the scrubber hits on every tick: no `device.makeBuffer`,
                // no re-tessellation, just an integer.
                batch.drawVertexCount = object.visibleVertexCount.map { min($0, batch.vertexCount) } ?? batch.vertexCount
                batchesByID[object.id] = batch
                updated.append(batch)
            } else if let batch = buildRenderBatch(from: object) {
                batchesByID[object.id] = batch
                updated.append(batch)
            }
        }

        // Drop cached buffers for objects no longer in the scene.
        for id in batchesByID.keys where !keepIDs.contains(id) {
            batchesByID.removeValue(forKey: id)
        }

        renderBatches = updated
    }

    /// Centers and zooms the camera to frame everything currently in
    /// `lastObjects`, with some breathing room around it. Only ever runs
    /// once per `MetalRenderer` instance (i.e. once per time the canvas
    /// appears) — after that the person's own pan/zoom takes over.
    ///
    /// Called from `draw(in:)` rather than `drawableSizeWillChange` because
    /// that callback fires *before* the new size takes effect — reading
    /// `view.drawableSize` there returns the stale (often zero) value, which
    /// silently failed the size check every time and left the camera at its
    /// untouched default target of (0, 0, 0). `draw(in:)` runs every frame
    /// with a guaranteed-current `drawableSize`, so this is self-correcting
    /// regardless of whether geometry or layout arrives first.
    private func attemptInitialFit(viewSize: CGSize, padding: Float = 1.3) {
        guard !hasFittedInitialContent else {
            return
        }
        guard viewSize.width > 0, viewSize.height > 0 else {
            return
        }
        guard let (center, radius) = boundingSphere(of: lastObjects) else {
            return
        }

        let aspect = Float(viewSize.width / viewSize.height)
        let paddedRadius = radius * padding // padding > 1 leaves margin around the content

        // Orthographic half-extents at the current distance are
        // `distance * tan(fov/2)` vertically and that times aspect
        // horizontally; solve for the distance that makes both at least
        // `paddedRadius` so the content fits regardless of the view's shape.
        let halfHeight = paddedRadius / min(aspect, 1)
        let requiredDistance = halfHeight / tan(camera.fov * 0.5)

        camera.target = center
        camera.distance = min(max(requiredDistance, 2.0), 2000.0)

        hasFittedInitialContent = true
    }

    /// Bounding sphere (center + radius) of every point across `objects`,
    /// used only for framing the camera — rotation-invariant, so it doesn't
    /// matter that the camera can orbit.
    private func boundingSphere(of objects: [RenderObject]) -> (center: SIMD3<Float>, radius: Float)? {
        var minPoint = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxPoint = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var found = false

        for object in objects {
            for point in object.points {
                found = true
                minPoint = simd_min(minPoint, point)
                maxPoint = simd_max(maxPoint, point)
            }
        }

        guard found else {
            return nil
        }

        let center = (minPoint + maxPoint) * 0.5
        let radius = max(simd_length(maxPoint - minPoint) * 0.5, 0.001)
        return (center, radius)
    }

}

private extension MetalRenderer {

    /// Binds one batch's uniforms/buffer and issues its draw call. Shared by
    /// both the visible and hidden passes in `draw(in:)` — they differ only
    /// in which depth state is bound and what dash length they pass in.
    func drawBatch(_ batch: RenderBatch, mvp: matrix_float4x4, dashLength: Float, encoder: MTLRenderCommandEncoder) {
        var uniforms = Uniforms(modelViewProjectionMatrix: mvp, dashLength: dashLength)

        // Bind uniforms to Vertex Shader (buffer index 1)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

        // Bind uniforms to Fragment Shader (buffer index 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

        // Bind vertex geometry buffer (buffer index 0)
        encoder.setVertexBuffer(batch.vertexBuffer, offset: 0, index: 0)

        // Draw primitives — `drawVertexCount`, not `vertexCount`: the buffer
        // may hold more than we want visible right now (see `RenderBatch`).
        encoder.drawPrimitives(type: batch.primitiveType, vertexStart: 0, vertexCount: batch.drawVertexCount)
    }

    /// Same binding dance as `drawBatch`, for occluder-face geometry: always
    /// `dashLength: 0` (no discards — a face pre-pass needs to be solid to
    /// be useful) and always `.triangle` (occluder buffers are triangle
    /// lists regardless of what primitive type their owning batch's edges use).
    func drawOccluder(_ buffer: MTLBuffer, vertexCount: Int, mvp: matrix_float4x4, encoder: MTLRenderCommandEncoder) {
        var uniforms = Uniforms(modelViewProjectionMatrix: mvp, dashLength: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
    }
}

extension MetalRenderer: MTKViewDelegate {

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        camera.aspectRatio = Float(size.width / size.height)
    }

    func draw(in view: MTKView) {

        attemptInitialFit(viewSize: view.drawableSize)

        guard let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        let mvp = camera.updateMatrix() // same for every batch/pass this frame

        // Pass 0 — occluder faces. Depth-only, color writes off, drawn
        // before any edges so their surfaces are already in the depth
        // buffer when the edge passes run. A small depth bias pushes these
        // faces a hair farther away than they really are, so an edge lying
        // exactly on its own solid's surface reliably wins pass 1 instead
        // of z-fighting with the face it's coincident with.
        renderEncoder.setRenderPipelineState(depthOnlyPipelineState)
        renderEncoder.setDepthStencilState(depthStateVisible)
        renderEncoder.setDepthBias(occluderDepthBias, slopeScale: occluderDepthBiasSlope, clamp: 0)
        for batch in renderBatches {
            guard let occluderBuffer = batch.occluderBuffer, batch.occluderVertexCount > 0 else {
                continue
            }
            drawOccluder(occluderBuffer, vertexCount: batch.occluderVertexCount, mvp: mvp, encoder: renderEncoder)
        }
        renderEncoder.setDepthBias(0, slopeScale: 0, clamp: 0)
        renderEncoder.setRenderPipelineState(pipelineState)

        // Pass 1 — visible geometry. Normal depth test, writes depth, drawn
        // however each object specifies (solid, or its own dash pattern).
        renderEncoder.setDepthStencilState(depthStateVisible)
        for batch in renderBatches {
            drawBatch(batch, mvp: mvp, dashLength: batch.isDashed ? batch.dashLength : 0.0, encoder: renderEncoder)
        }

        // Pass 2 — hidden geometry. Re-draws every batch with the depth
        // test inverted, so only the portions occluded by pass 0 or pass 1
        // survive. Only stock gets the dashed technical-drawing treatment
        // here; everything else (toolpaths, tool, axes) is redrawn solid,
        // so it stays fully visible — just not dashed — wherever it's
        // behind the stock.
        if showHiddenLines {
            renderEncoder.setDepthStencilState(depthStateHidden)
            for batch in renderBatches {
                let dash: Float
                if batch.role == .stock {
                    dash = batch.isDashed ? batch.dashLength : hiddenLineDashLength
                } else {
                    dash = batch.isDashed ? batch.dashLength : 0.0
                }
                drawBatch(batch, mvp: mvp, dashLength: dash, encoder: renderEncoder)
            }
        }

        renderEncoder.endEncoding()
        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }
}
