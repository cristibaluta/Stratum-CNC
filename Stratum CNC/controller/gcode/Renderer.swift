//
//  Renderer.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.08.2026.
//

import MetalKit
import simd

@MainActor
final class Renderer: NSObject, MTKViewDelegate {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var vertexBuffer: MTLBuffer?
    private weak var metalView: MTKView?

    private var viewportSize = SIMD2<Float>(1, 1)

    // MARK: Camera

    // Orbit angles.
    //
    // yaw:
    //   Horizontal rotation around world Y.
    //
    // pitch:
    //   Vertical rotation. Clamped so the camera never flips upside down.
    private var yaw: Float = .pi / 4
    private var pitch: Float = .pi / 6

    // Distance used by the orthographic camera as well as
    // the camera's position relative to its target.
    private var cameraDistance: Float = 1000
    private var zoom: Float = 100

    private let minZoom: Float = 0.1
    private let maxZoom: Float = 100_000

    // The point the camera is looking at.
    // Panning moves this point.
    private var cameraTarget = SIMD3<Float>(0, 0, 0)

    private var lastPanTranslation = CGPoint.zero

    private var axisVertices: [SIMD3<Float>] {
        // Axis lines + arrowheads
        let axisSize: Float = 3.0
        let arrowSize: Float = 0.25

        let vertices: [SIMD3<Float>] = [

            // X axis
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(axisSize, 0, 0),

            // X arrowhead
            SIMD3<Float>(axisSize, 0, 0),
            SIMD3<Float>(axisSize - arrowSize, arrowSize, 0),

            SIMD3<Float>(axisSize, 0, 0),
            SIMD3<Float>(axisSize - arrowSize, -arrowSize, 0),

            // Y axis
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(0, axisSize, 0),

            // Y arrowhead
            SIMD3<Float>(0, axisSize, 0),
            SIMD3<Float>(arrowSize, axisSize - arrowSize, 0),

            SIMD3<Float>(0, axisSize, 0),
            SIMD3<Float>(-arrowSize, axisSize - arrowSize, 0),

            // Z axis
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(0, 0, axisSize),

            // Z arrowhead
            SIMD3<Float>(0, 0, axisSize),
            SIMD3<Float>(arrowSize, 0, axisSize - arrowSize),

            SIMD3<Float>(0, 0, axisSize),
            SIMD3<Float>(-arrowSize, 0, axisSize - arrowSize),
        ]

        return vertices
    }

    private func boxVertices(
        origin: SIMD3<Float>,
        width: Float,
        height: Float,
        depth: Float
    ) -> [SIMD3<Float>] {

        let x = width / 2
        let y = height / 2
        let z = depth / 2

        let minX = origin.x - x
        let maxX = origin.x + x
        let minY = origin.y - y
        let maxY = origin.y + y
        let minZ = origin.z - z
        let maxZ = origin.z + z

        return [
            // Bottom
            SIMD3(minX, minY, minZ), SIMD3(maxX, minY, minZ),
            SIMD3(maxX, minY, minZ), SIMD3(maxX, minY, maxZ),
            SIMD3(maxX, minY, maxZ), SIMD3(minX, minY, maxZ),
            SIMD3(minX, minY, maxZ), SIMD3(minX, minY, minZ),

            // Top
            SIMD3(minX, maxY, minZ), SIMD3(maxX, maxY, minZ),
            SIMD3(maxX, maxY, minZ), SIMD3(maxX, maxY, maxZ),
            SIMD3(maxX, maxY, maxZ), SIMD3(minX, maxY, maxZ),
            SIMD3(minX, maxY, maxZ), SIMD3(minX, maxY, minZ),

            // Vertical edges
            SIMD3(minX, minY, minZ), SIMD3(minX, maxY, minZ),
            SIMD3(maxX, minY, minZ), SIMD3(maxX, maxY, minZ),
            SIMD3(maxX, minY, maxZ), SIMD3(maxX, maxY, maxZ),
            SIMD3(minX, minY, maxZ), SIMD3(minX, maxY, maxZ)
        ]
    }

    // MARK: Init

    override init() {

        guard
            let device = MTLCreateSystemDefaultDevice(),
            let commandQueue = device.makeCommandQueue()
        else {
            fatalError("Could not create Metal device")
        }

        self.device = device
        self.commandQueue = commandQueue

        // ---------------------------------------------------------
        // Metal pipeline
        // ---------------------------------------------------------

        guard let library = device.makeDefaultLibrary() else {
            fatalError("Could not load Metal library")
        }

        guard
            let vertexFunction = library.makeFunction(name: "line_vertex"),
            let fragmentFunction = library.makeFunction(name: "line_fragment")
        else {
            fatalError("Could not load Metal functions")
        }

        let descriptor = MTLRenderPipelineDescriptor()

        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            self.pipelineState =
                try device.makeRenderPipelineState(
                    descriptor: descriptor
                )
        } catch {
            fatalError(
                "Could not create pipeline: \(error)"
            )
        }

        super.init()

        // ---------------------------------------------------------
        // Geometry
        // ---------------------------------------------------------

        let vertices: [SIMD3<Float>] =
            axisVertices + boxVertices(
                origin: SIMD3<Float>(75, 12.5, 1),
                width: 150,
                height: 25,
                depth: 2
            )

        guard let buffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<SIMD3<Float>>.stride * vertices.count,
            options: []
        ) else {
            fatalError("Could not create vertex buffer")
        }

        self.vertexBuffer = buffer
    }

    func attach(to view: MTKView) {
        metalView = view

        view.delegate = self
        view.isPaused = true
        view.enableSetNeedsDisplay = true

        view.setNeedsDisplay(view.bounds)
    }
    
    // MARK: Camera

    private func cameraPosition() -> SIMD3<Float> {

        let cosPitch = cos(pitch)

        let direction = SIMD3<Float>(
            cosPitch * sin(yaw),
            sin(pitch),
            cosPitch * cos(yaw)
        )

        return cameraTarget + direction * cameraDistance
    }

    private func viewMatrix() -> float4x4 {

        let eye = cameraPosition()

        return float4x4(
            lookAt: eye,
            target: cameraTarget,
            up: SIMD3<Float>(0, 1, 0)
        )
    }

    private func projectionMatrix() -> float4x4 {

        let aspect =
            viewportSize.x /
            max(viewportSize.y, 1)

        let height = zoom
        let width = height * aspect

        return float4x4(
            orthographicLeft: -width / 2,
            right: width / 2,
            bottom: -height / 2,
            top: height / 2,
            nearZ: -100_000,
            farZ: 100_000
        )
    }

    // MARK: Camera helpers

    private func orbit(
        dx: Float,
        dy: Float
    ) {

        let sensitivity: Float = 0.008

        // Horizontal movement:
        // orbit around the global Y axis.
        yaw -= dx * sensitivity

        // Vertical movement:
        // change the explicit pitch angle.
        //
        // This is intentionally NOT calculated from the
        // current camera quaternion. That was the source of
        // the unpredictable vertical behavior.
        pitch -= dy * sensitivity

        // Prevent the camera from flipping upside down.
        let limit = Float.pi / 2 - 0.01

        pitch = max(
            -limit,
            min(limit, pitch)
        )
    }

    private func pan(
        dx: Float,
        dy: Float
    ) {

        // Camera position relative to target.
        let direction = simd_normalize(
            cameraPosition() - cameraTarget
        )

        // Screen-right vector.
        //
        // We use the world's Y axis as the reference so
        // horizontal panning remains stable.
        let worldUp = SIMD3<Float>(0, 1, 0)

        var right = simd_cross(
            worldUp,
            direction
        )

        right = simd_normalize(right)

        // Screen-up vector.
        let up = simd_normalize(
            simd_cross(
                direction,
                right
            )
        )

        // Scale panning with zoom level.
        //
        // This makes dragging feel consistent at different
        // zoom levels.
        let panScale = zoom * 0.002

        // Dragging right moves the scene right.
        // Dragging down moves the scene down.
        cameraTarget -= right * dx * panScale
        cameraTarget += up * dy * panScale
    }

    // MARK: Mouse / Trackpad pan

    @objc
    func handlePan(
        _ gesture: NSPanGestureRecognizer
    ) {

        let translation =
            gesture.translation(in: gesture.view)

        if gesture.state == .began {

            lastPanTranslation = translation

            return
        }

        guard gesture.state == .changed else {
            return
        }

        let dx = Float(
            translation.x -
            lastPanTranslation.x
        )

        let dy = Float(
            translation.y -
            lastPanTranslation.y
        )

        lastPanTranslation = translation

        // Shift + drag = orbit
        // Normal drag   = pan
        if NSEvent.modifierFlags.contains(.shift) {
            orbit(
                dx: dx,
                dy: -dy
            )
        } else {
            pan(
                dx: dx,
                dy: -dy
            )
        }

        requestRedraw()
        printCamera()
    }

    private func requestRedraw() {
        guard let metalView else { return }
        metalView.setNeedsDisplay(metalView.bounds)
    }

    // MARK: Trackpad zoom

    @objc
    func handleMagnification( _ gesture: NSMagnificationGestureRecognizer) {

        if gesture.state == .changed {

            let amount =
                Float(gesture.magnification)

            zoom *= 1 - amount

            zoom = max(
                minZoom,
                min(maxZoom, zoom)
            )

            gesture.magnification = 0

            requestRedraw()
            printCamera()
        }
    }

    // MARK: Debug

    private func printCamera() {

        let position = cameraPosition()

        print("Camera target: x: \(cameraTarget.x) y: \(cameraTarget.y) z: \(cameraTarget.z)   position: x: \(position.x) y: \(position.y) z: \(position.z)   camera distance: \(cameraDistance) mm   zoom: \(zoom) mm visible   yaw: \(yaw)   pitch: \(pitch)")
    }

    // MARK: MTKViewDelegate

    func mtkView(
        _ view: MTKView,
        drawableSizeWillChange size: CGSize
    ) {
        viewportSize = SIMD2<Float>(
            Float(size.width),
            Float(size.height)
        )

        requestRedraw()
    }

    func draw(
        in view: MTKView
    ) {

        guard
            let drawable = view.currentDrawable,
            let descriptor = view.currentRenderPassDescriptor,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }

        let encoder =
            commandBuffer.makeRenderCommandEncoder(
                descriptor: descriptor
            )!

        encoder.setRenderPipelineState(
            pipelineState
        )

        var viewMatrix = viewMatrix()
        var projectionMatrix = projectionMatrix()

        encoder.setVertexBytes(
            &viewMatrix,
            length: MemoryLayout<float4x4>.stride,
            index: 1
        )

        encoder.setVertexBytes(
            &projectionMatrix,
            length: MemoryLayout<float4x4>.stride,
            index: 2
        )

        encoder.setVertexBuffer(
            vertexBuffer,
            offset: 0,
            index: 0
        )

        // X axis + arrowhead
        drawLine(
            encoder: encoder,
            vertexStart: 0,
            color: SIMD4<Float>(1, 0, 0, 1)
        )

        drawLine(
            encoder: encoder,
            vertexStart: 2,
            color: SIMD4<Float>(1, 0, 0, 1)
        )

        drawLine(
            encoder: encoder,
            vertexStart: 4,
            color: SIMD4<Float>(1, 0, 0, 1)
        )

        // Y axis + arrowhead
        drawLine(
            encoder: encoder,
            vertexStart: 6,
            color: SIMD4<Float>(0, 1, 0, 1)
        )

        drawLine(
            encoder: encoder,
            vertexStart: 8,
            color: SIMD4<Float>(0, 1, 0, 1)
        )

        drawLine(
            encoder: encoder,
            vertexStart: 10,
            color: SIMD4<Float>(0, 1, 0, 1)
        )

        // Z axis + arrowhead
        drawLine(
            encoder: encoder,
            vertexStart: 12,
            color: SIMD4<Float>(0, 0.4, 1, 1)
        )

        drawLine(
            encoder: encoder,
            vertexStart: 14,
            color: SIMD4<Float>(0, 0.4, 1, 1)
        )

        drawLine(
            encoder: encoder,
            vertexStart: 16,
            color: SIMD4<Float>(0, 0.4, 1, 1)
        )

        // Cube
        let cubeColor =
            SIMD4<Float>(1, 1, 1, 1)

        for i in stride(
            from: 18,
            to: 42,
            by: 2
        ) {

            drawLine(
                encoder: encoder,
                vertexStart: i,
                color: cubeColor
            )
        }

        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func drawLine(
        encoder: MTLRenderCommandEncoder,
        vertexStart: Int,
        color: SIMD4<Float>
    ) {

        var color = color

        encoder.setFragmentBytes(
            &color,
            length: MemoryLayout<SIMD4<Float>>.stride,
            index: 0
        )

        encoder.drawPrimitives(
            type: .line,
            vertexStart: vertexStart,
            vertexCount: 2
        )
    }
}

// MARK: - Look-at matrix

extension float4x4 {

    init(
        lookAt eye: SIMD3<Float>,
        target: SIMD3<Float>,
        up: SIMD3<Float>
    ) {

        let z =
            simd_normalize(
                eye - target
            )

        let x =
            simd_normalize(
                simd_cross(up, z)
            )

        let y =
            simd_cross(z, x)

        self.init(
            SIMD4<Float>(
                x.x, y.x, z.x, 0
            ),

            SIMD4<Float>(
                x.y, y.y, z.y, 0
            ),

            SIMD4<Float>(
                x.z, y.z, z.z, 0
            ),

            SIMD4<Float>(
                -simd_dot(x, eye),
                -simd_dot(y, eye),
                -simd_dot(z, eye),
                1
            )
        )
    }

    init(
        perspectiveFov fov: Float,
        aspect: Float,
        nearZ: Float,
        farZ: Float
    ) {

        let yScale =
            1 / tan(fov * 0.5)

        let xScale =
            yScale / aspect

        let zRange =
            farZ - nearZ

        self.init(
            SIMD4<Float>(
                xScale, 0, 0, 0
            ),

            SIMD4<Float>(
                0, yScale, 0, 0
            ),

            SIMD4<Float>(
                0,
                0,
                -(farZ + nearZ) / zRange,
                -1
            ),

            SIMD4<Float>(
                0,
                0,
                -(2 * farZ * nearZ) / zRange,
                0
            )
        )
    }
}

// MARK: - Orthographic matrix

extension float4x4 {

    init(
        orthographicLeft left: Float,
        right: Float,
        bottom: Float,
        top: Float,
        nearZ: Float,
        farZ: Float
    ) {

        self.init(
            SIMD4<Float>(
                2 / (right - left),
                0,
                0,
                0
            ),

            SIMD4<Float>(
                0,
                2 / (top - bottom),
                0,
                0
            ),

            SIMD4<Float>(
                0,
                0,
                -2 / (farZ - nearZ),
                0
            ),

            SIMD4<Float>(
                -(right + left) / (right - left),
                -(top + bottom) / (top - bottom),
                -(farZ + nearZ) / (farZ - nearZ),
                1
            )
        )
    }
}

// MARK: - Translation matrix

extension float4x4 {

    init(translation: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4<Float>(translation.x, translation.y, translation.z, 1)
    }
}
