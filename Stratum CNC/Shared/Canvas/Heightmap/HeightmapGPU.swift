//
//
//  HeightmapGPU.swift
//  Stratum CNC
//
//  The 2.5D stock preview, carved and drawn on the GPU.
//
//  Every cutting segment of the program becomes one instance of a quad that covers its swept
//  footprint. A render pass draws them top-down into a height texture; the fragment shader works
//  out the exact height the tool leaves under each pixel and writes it as colour and as depth, so
//  the depth test (`less`) keeps the lowest one: carving, in any order, with no CPU loop. Scrubbing
//  forward only draws the newly reached segments on top of what is already there; scrubbing back
//  clears and redraws. The surface is drawn from that texture (see Shaders.metal).
//
//  Handles rectangular stock. Round stock keeps the CPU path (`HeightmapGrid`).
//

import Foundation
import Metal
import simd

/// Everything the GPU heightmap needs for one frame's worth of state. `serial` changes whenever
/// anything does, so the view can tell a new request from a re-run of its body without comparing
/// the (large) segment array.
struct HeightmapGPURequest: Equatable {
    let serial: Int
    /// Changes only when a different program is loaded, so the instances built from `segments`
    /// can be kept across scrubs and every other change.
    let programID: Int
    /// Rectangular stock, in mm. Its top is Z 0 and its XY starts at the origin (same frame as `HeightmapGrid`).
    let width: Float
    let height: Float
    let depth: Float
    /// The whole program, in file order. Not a prefix: scrubbing changes only `segmentCount`.
    let segments: [ToolpathSegment]
    /// How many leading segments are carved.
    let segmentCount: Int
    let tools: ToolSchedule
    let cellSize: Float
    /// The job's XY offset, baked into the carve.
    let offset: SIMD2<Float>

    static func == (lhs: HeightmapGPURequest, rhs: HeightmapGPURequest) -> Bool {
        lhs.serial == rhs.serial
    }
}

// MARK: - Mirrors of the structs in Shaders.metal

private struct CarveParams {
    var origin: SIMD2<Float>
    var extent: SIMD2<Float>
    var offset: SIMD2<Float>
    var bottomZ: Float
    var range: Float
}

private struct CarveToolInfo {
    var radius: Float
    var coneSlope: Float
    var kind: UInt32
    var padding: UInt32 = 0
}

private struct CarveInstance {
    var a: SIMD4<Float>
    var b: SIMD4<Float>
}

private struct SurfaceParams {
    var columns: UInt32
    var rows: UInt32
    var spacing: SIMD2<Float>
}

final class HeightmapGPU {

    /// Most samples along one side. 2048² is 4 M samples (8 M triangles): finer than any
    /// stock needs, and bounds the index buffer at about 100 MB.
    private static let maxCellsPerSide = 2047

    private struct Layout: Equatable {
        var columns: Int
        var rows: Int
        var width: Float
        var height: Float
        var depth: Float
        var offset: SIMD2<Float>

        var spacing: SIMD2<Float> {
            SIMD2(width / Float(columns), height / Float(rows))
        }
        var samples: (x: Int, y: Int) {
            (columns + 1, rows + 1)
        }
    }

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let carvePipeline: MTLRenderPipelineState
    private let carveDepthState: MTLDepthStencilState
    private let surfacePipeline: MTLRenderPipelineState
    private let skirtPipeline: MTLRenderPipelineState

    private var layout: Layout?
    private var heightTexture: MTLTexture?
    private var depthTexture: MTLTexture?
    private var indexBuffer: MTLBuffer?
    private var indexCount = 0

    private var programID: Int?
    private var toolsKey: ToolSchedule?
    private var instanceBuffer: MTLBuffer?
    private var toolTable: [CarveToolInfo] = []
    /// For each instance, the index of the program segment it came from (ascending).
    private var segmentIndices: [UInt32] = []
    private var carvedInstances = 0

    /// True while there is a carved surface to draw.
    private(set) var isActive = false

    init?(device: MTLDevice,
          queue: MTLCommandQueue,
          colorPixelFormat: MTLPixelFormat,
          depthPixelFormat: MTLPixelFormat,
          sampleCount: Int) {

        guard let library = device.makeDefaultLibrary(),
              let carveVertex = library.makeFunction(name: "vertex_hmcarve"),
              let carveFragment = library.makeFunction(name: "fragment_hmcarve"),
              let surfaceVertex = library.makeFunction(name: "vertex_heightmap_surface"),
              let skirtVertex = library.makeFunction(name: "vertex_heightmap_skirt"),
              let shadeFragment = library.makeFunction(name: "fragment_heightmap") else {
            print("❌ Error: Could not find GPU heightmap shader functions.")
            return nil
        }

        let carve = MTLRenderPipelineDescriptor()
        carve.vertexFunction = carveVertex
        carve.fragmentFunction = carveFragment
        carve.colorAttachments[0].pixelFormat = .r32Float
        carve.depthAttachmentPixelFormat = .depth32Float
        carve.rasterSampleCount = 1

        func surface(_ vertex: MTLFunction) -> MTLRenderPipelineDescriptor {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = shadeFragment
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
            descriptor.depthAttachmentPixelFormat = depthPixelFormat
            descriptor.rasterSampleCount = sampleCount
            return descriptor
        }

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true

        guard let carvePipeline = try? device.makeRenderPipelineState(descriptor: carve),
              let surfacePipeline = try? device.makeRenderPipelineState(descriptor: surface(surfaceVertex)),
              let skirtPipeline = try? device.makeRenderPipelineState(descriptor: surface(skirtVertex)),
              let carveDepthState = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            print("❌ Error: Could not build the GPU heightmap pipelines.")
            return nil
        }

        self.device = device
        self.queue = queue
        self.carvePipeline = carvePipeline
        self.carveDepthState = carveDepthState
        self.surfacePipeline = surfacePipeline
        self.skirtPipeline = skirtPipeline
    }

    // MARK: Updating

    /// Stops drawing the surface (resources and carve state stay, so coming back is cheap).
    func clear() {
        isActive = false
    }

    /// Brings the height texture to `request.segmentCount` segments carved: only the new ones
    /// when moving forward on the same program, a clean redraw for anything else.
    func apply(_ request: HeightmapGPURequest) {
        let newLayout = makeLayout(for: request)
        var restart = false

        if newLayout != layout || heightTexture == nil {
            guard allocate(newLayout) else {
                isActive = false
                return
            }
            restart = true
        }

        if request.programID != programID || request.tools != toolsKey {
            rebuildInstances(segments: request.segments, tools: request.tools)
            programID = request.programID
            toolsKey = request.tools
            restart = true
        }

        let needed = instanceCount(beforeSegment: request.segmentCount)
        if restart || needed < carvedInstances {
            carve(range: 0..<needed, clearing: true)
        } else if needed > carvedInstances {
            carve(range: carvedInstances..<needed, clearing: false)
        }
        carvedInstances = needed
        isActive = true
    }

    private func makeLayout(for request: HeightmapGPURequest) -> Layout {
        let cell = max(request.cellSize, 0.005)
        let columns = max(1, min(Self.maxCellsPerSide, Int((request.width / cell).rounded(.up))))
        let rows = max(1, min(Self.maxCellsPerSide, Int((request.height / cell).rounded(.up))))
        return Layout(columns: columns, rows: rows,
                      width: request.width, height: request.height, depth: request.depth,
                      offset: request.offset)
    }

    // MARK: Resources

    private func allocate(_ layout: Layout) -> Bool {
        let (samplesX, samplesY) = layout.samples

        let heightDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float,
                                                                        width: samplesX, height: samplesY,
                                                                        mipmapped: false)
        heightDescriptor.usage = [.renderTarget, .shaderRead]
        heightDescriptor.storageMode = .private

        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
                                                                       width: samplesX, height: samplesY,
                                                                       mipmapped: false)
        depthDescriptor.usage = [.renderTarget]
        depthDescriptor.storageMode = .private

        guard let height = device.makeTexture(descriptor: heightDescriptor),
              let depth = device.makeTexture(descriptor: depthDescriptor) else {
            return false
        }

        // Two triangles per lattice cell, reused until the lattice size changes.
        if indexBuffer == nil || self.layout?.columns != layout.columns || self.layout?.rows != layout.rows {
            var indices: [UInt32] = []
            indices.reserveCapacity(layout.columns * layout.rows * 6)
            let stride = UInt32(samplesX)
            for row in 0..<layout.rows {
                for col in 0..<layout.columns {
                    let a = UInt32(row) * stride + UInt32(col)
                    let b = a + 1
                    let c = a + stride + 1
                    let d = a + stride
                    indices.append(contentsOf: [a, b, c, a, c, d])
                }
            }
            guard let buffer = device.makeBuffer(bytes: indices,
                                                 length: indices.count * MemoryLayout<UInt32>.stride,
                                                 options: .storageModeShared) else {
                return false
            }
            indexBuffer = buffer
            indexCount = indices.count
        }

        heightTexture = height
        depthTexture = depth
        self.layout = layout
        return true
    }

    /// Turns the program into one instance per cutting segment, each tagged with its tool. A
    /// segment whose tool has no assignment carves nothing, same as the CPU path.
    private func rebuildInstances(segments: [ToolpathSegment], tools: ToolSchedule) {
        var geometries: [ToolGeometry] = []
        var table: [CarveToolInfo] = []

        func toolIndex(_ tool: ToolGeometry?) -> Int? {
            guard let tool else {
                return nil
            }
            if let existing = geometries.firstIndex(of: tool) {
                return existing
            }
            let radius = ToolFootprint.radius(for: tool)
            var kind: UInt32 = 0
            var slope: Float = 0
            switch tool.shape {
                case .flat:
                    kind = 0
                case .ball:
                    kind = 1
                case .cone:
                    // No usable angle: a flat disc, as `ToolFootprint.surfaceZ` does.
                    if let angle = tool.tipAngle, angle > 0, angle < 180 {
                        kind = 2
                        slope = Float(1 / tan(angle / 2 * Double.pi / 180))
                    }
            }
            geometries.append(tool)
            table.append(CarveToolInfo(radius: radius, coneSlope: slope, kind: kind))
            return geometries.count - 1
        }

        let initialIndex = toolIndex(tools.initial)
        let entryLines = tools.entries.map(\.fromLine)
        let entryIndices = tools.entries.map { toolIndex($0.tool) }

        var instances: [CarveInstance] = []
        var indices: [UInt32] = []
        instances.reserveCapacity(segments.count)
        indices.reserveCapacity(segments.count)

        let cutting = ToolpathFlags.cutting | ToolpathFlags.arc
        for (index, segment) in segments.enumerated() where segment.flags & cutting != 0 {
            // The tool of the last entry at or before this segment's line.
            var low = 0
            var high = entryLines.count
            while low < high {
                let mid = (low + high) / 2
                if entryLines[mid] <= segment.lineNumber {
                    low = mid + 1
                } else {
                    high = mid
                }
            }
            let tool = low == 0 ? initialIndex : entryIndices[low - 1]
            guard let tool, table[tool].radius > 0 else {
                continue
            }
            instances.append(CarveInstance(a: SIMD4(segment.start, Float(tool)),
                                           b: SIMD4(segment.end, 0)))
            indices.append(UInt32(index))
        }

        toolTable = table
        segmentIndices = indices
        carvedInstances = 0
        instanceBuffer = instances.isEmpty ? nil : device.makeBuffer(bytes: instances,
                                                                     length: instances.count * MemoryLayout<CarveInstance>.stride,
                                                                     options: .storageModeShared)
    }

    /// How many instances come from the first `segmentCount` segments of the program.
    private func instanceCount(beforeSegment segmentCount: Int) -> Int {
        var low = 0
        var high = segmentIndices.count
        while low < high {
            let mid = (low + high) / 2
            if Int(segmentIndices[mid]) < segmentCount {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    // MARK: Carving

    private func carve(range: Range<Int>, clearing: Bool) {
        guard let layout, let heightTexture, let depthTexture,
              let commandBuffer = queue.makeCommandBuffer() else {
            return
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = heightTexture
        pass.colorAttachments[0].loadAction = clearing ? .clear : .load
        pass.colorAttachments[0].storeAction = .store
        // The uncut top: height 0, depth 1 (the far plane, which nothing at or above it can beat).
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.depthAttachment.texture = depthTexture
        pass.depthAttachment.loadAction = clearing ? .clear : .load
        pass.depthAttachment.storeAction = .store
        pass.depthAttachment.clearDepth = 1

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            return
        }

        if !range.isEmpty, let instanceBuffer, !toolTable.isEmpty {
            let spacing = layout.spacing
            var params = CarveParams(origin: SIMD2(-spacing.x / 2, -spacing.y / 2),
                                     extent: SIMD2(layout.width + spacing.x, layout.height + spacing.y),
                                     offset: layout.offset,
                                     bottomZ: -layout.depth,
                                     range: max(layout.depth, 0.001))

            encoder.setRenderPipelineState(carvePipeline)
            encoder.setDepthStencilState(carveDepthState)
            encoder.setCullMode(.none)
            encoder.setVertexBytes(&params, length: MemoryLayout<CarveParams>.stride, index: 0)
            encoder.setFragmentBytes(&params, length: MemoryLayout<CarveParams>.stride, index: 0)
            encoder.setVertexBuffer(instanceBuffer, offset: range.lowerBound * MemoryLayout<CarveInstance>.stride, index: 1)
            toolTable.withUnsafeBytes { bytes in
                encoder.setVertexBytes(bytes.baseAddress!, length: bytes.count, index: 2)
                encoder.setFragmentBytes(bytes.baseAddress!, length: bytes.count, index: 2)
            }
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: range.count)
        }

        encoder.endEncoding()
        commandBuffer.commit()
    }

    // MARK: Drawing

    /// Draws the carved surface, its four sides and its bottom. `offset` is where the stock sits
    /// in the scene (the anchor); the job offset is already part of the carve.
    func draw(encoder: MTLRenderCommandEncoder,
              mvp: matrix_float4x4,
              lightDirection: SIMD3<Float>,
              baseColor: SIMD4<Float>,
              ambient: Float,
              depthDarkening: Float,
              offset: SIMD2<Float>) {
        guard isActive, let layout, let heightTexture, let indexBuffer else {
            return
        }

        var uniforms = HeightmapUniforms(modelViewProjectionMatrix: mvp,
                                         lightDirection: lightDirection,
                                         baseColor: baseColor,
                                         ambient: ambient,
                                         topZ: 0,
                                         bottomZ: -layout.depth,
                                         depthDarkening: depthDarkening,
                                         offset: offset)
        var surface = SurfaceParams(columns: UInt32(layout.columns + 1),
                                    rows: UInt32(layout.rows + 1),
                                    spacing: layout.spacing)

        // Winding doesn't matter here: heights are single-valued, and the sides and bottom close it.
        encoder.setCullMode(.none)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<HeightmapUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<HeightmapUniforms>.stride, index: 1)
        encoder.setVertexBytes(&surface, length: MemoryLayout<SurfaceParams>.stride, index: 2)
        encoder.setVertexTexture(heightTexture, index: 0)

        encoder.setRenderPipelineState(surfacePipeline)
        encoder.drawIndexedPrimitives(type: .triangle,
                                      indexCount: indexCount,
                                      indexType: .uint32,
                                      indexBuffer: indexBuffer,
                                      indexBufferOffset: 0)

        encoder.setRenderPipelineState(skirtPipeline)
        let skirtQuads = 2 * layout.columns + 2 * layout.rows + 1
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: skirtQuads * 6)
    }
}
