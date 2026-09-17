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
        renderBatches = objects.compactMap { buildRenderBatch(from: $0) }
    }

}

extension MetalRenderer: MTKViewDelegate {

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        camera.aspectRatio = Float(size.width / size.height)
    }

    func draw(in view: MTKView) {

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
