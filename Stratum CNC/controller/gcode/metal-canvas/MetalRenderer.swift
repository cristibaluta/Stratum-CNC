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

struct RenderBatch {
    var vertexBuffer: MTLBuffer
    var vertexCount: Int
    var primitiveType: MTLPrimitiveType
    var isDashed: Bool = false
    var dashLength: Float = 5.0
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
    var renderBatches: [RenderBatch] = []

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

        renderBatches = [buildRenderBatch(forPoints: [], color: SIMD4<Float>(0.6, 0.2, 0.85, 1.0))!]
    }

    static func stockBoxVertices(color: SIMD4<Float> = SIMD4<Float>(0.6, 0.2, 0.85, 1.0)) -> [RenderVertex] {
        let minX = Float(0)
        let maxX = Float(0 + 100)
        let minY = Float(0)
        let maxY = Float(0 + 50)
        let topZ = Float(0)
        let bottomZ = Float(0 - 10)

        let c000 = SIMD3<Float>(minX, minY, bottomZ)
        let c100 = SIMD3<Float>(maxX, minY, bottomZ)
        let c110 = SIMD3<Float>(maxX, maxY, bottomZ)
        let c010 = SIMD3<Float>(minX, maxY, bottomZ)
        let c001 = SIMD3<Float>(minX, minY, topZ)
        let c101 = SIMD3<Float>(maxX, minY, topZ)
        let c111 = SIMD3<Float>(maxX, maxY, topZ)
        let c011 = SIMD3<Float>(minX, maxY, topZ)

        let edges: [(SIMD3<Float>, SIMD3<Float>)] = [
            // Bottom face
            (c000, c100), (c100, c110), (c110, c010), (c010, c000),
            // Top face
            (c001, c101), (c101, c111), (c111, c011), (c011, c001),
            // Verticals joining the two faces
            (c000, c001), (c100, c101), (c110, c111), (c010, c011)
        ]

        var vertices: [RenderVertex] = []
        vertices.reserveCapacity(edges.count * 2)
        for (start, end) in edges {
            vertices.append(RenderVertex(position: start, color: color, dist: 0))
            vertices.append(RenderVertex(position: end, color: color, dist: 0))
        }
        return vertices
    }

    func buildRenderBatch(forPoints points: [SIMD3<Float>],
                          color: SIMD4<Float>,
                          isDashed: Bool = false,
                          dashLength: Float = 5.0) -> RenderBatch? {
        let vertices = Self.stockBoxVertices()
        guard !vertices.isEmpty,
              let buffer = device.makeBuffer(bytes: vertices,
                                             length: vertices.count * MemoryLayout<RenderVertex>.stride,
                                             options: .storageModeShared) else {
            return nil
        }
        return RenderBatch(vertexBuffer: buffer,
                           vertexCount: vertices.count,
                           primitiveType: .lineStrip,
                           isDashed: isDashed,
                           dashLength: dashLength)
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

    /// Redraw the screen
    func updateGeometry(batches: [RenderBatch]) {
//        self.renderBatches = batches
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
