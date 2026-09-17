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
    var vertexCount: Int
    var primitiveType: MTLPrimitiveType
    var isDashed: Bool = false
    var dashLength: Float = 5.0
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

    var camera = Camera()
    private var renderBatches: [RenderBatch] = []

    // Kept around only so we can compute a bounding sphere for the initial
    // "fit to screen" — the GPU buffers built into `renderBatches` don't carry
    // positions in a form that's cheap to read back.
    private var lastObjects: [RenderObject] = []
    private var hasFittedInitialContent = false

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
        return RenderBatch(vertexBuffer: buffer,
                           vertexCount: vertices.count,
                           primitiveType: object.primitive.mtlPrimitiveType,
                           isDashed: object.isDashed,
                           dashLength: object.dashLength)
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

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat

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
        pipelineDescriptor.vertexDescriptor = vertexDescriptor

        pipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }

    /// Rebuild GPU buffers from the model's plain-data description of what to draw.
    /// This is the seam: everything upstream of here (model, views) only ever
    /// deals with `RenderObject`; only this call touches `device.makeBuffer`.
    func updateGeometry(objects: [RenderObject]) {
        lastObjects = objects
        renderBatches = objects.compactMap { buildRenderBatch(from: $0) }
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

        renderEncoder.setRenderPipelineState(pipelineState)

        for batch in renderBatches {
            var uniforms = Uniforms(
                modelViewProjectionMatrix: camera.updateMatrix(),
                dashLength: batch.isDashed ? batch.dashLength : 0.0
            )

            // Bind uniforms to Vertex Shader (buffer index 1)
            renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

            // Bind uniforms to Fragment Shader (buffer index 1)
            renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

            // Bind vertex geometry buffer (buffer index 0)
            renderEncoder.setVertexBuffer(batch.vertexBuffer, offset: 0, index: 0)

            // Draw primitives
            renderEncoder.drawPrimitives(type: batch.primitiveType, vertexStart: 0, vertexCount: batch.vertexCount)
        }

        renderEncoder.endEncoding()
        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }
}
