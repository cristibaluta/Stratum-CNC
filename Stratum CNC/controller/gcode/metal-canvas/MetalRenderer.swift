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

@MainActor
class MetalRenderer: NSObject, MTKViewDelegate {
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var pipelineState: MTLRenderPipelineState!
    
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
    }

    private func setupPipeline(metalView: MTKView) {
        // The library is the metal shaders compiled
        guard let library = (try? device.makeDefaultLibrary(bundle: .main)) ?? device.makeDefaultLibrary() else {
            print("❌ Error: Could not load Metal shader library from Bundle.module.")
            return
        }

        guard let vertexFunction = library.makeFunction(name: "vertex_main"),
              let fragmentFunction = library.makeFunction(name: "fragment_main") else {
            print("❌ Error: Could not find shader functions.")
            return
        }
        guard let library = device.makeDefaultLibrary() else {
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

    func updateGeometry(batches: [RenderBatch]) {
        self.renderBatches = batches
    }

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
