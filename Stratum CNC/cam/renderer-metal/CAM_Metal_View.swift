//
//  CAM_Metal_View.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 21.09.2026.
//
import SwiftUI
import simd

/// What the CAM canvas is showing. Same canvas, same place on screen: only the
/// camera scheme and the geometry change.
enum CAMCanvasMode {
    /// Shapes and toolpaths, camera locked top-down, shapes selectable.
    case design2D
    /// STEP wireframe, free orbit like the controller's canvas, edges selectable.
    case step3D
}

@MainActor
struct CAM_Metal_View: View {

    @StateObject private var scene: CAMSceneModel
    let zoomModel: CanvasZoomModel
    let mode: CAMCanvasMode
    /// The STEP scene drawn in `.step3D`. `nil` while it is still loading or failed to load.
    let stepScene: STEPDocumentScene?
    /// The active setup's map: the 3D canvas turns the stock and model with it so that setup's
    /// face is the one facing up, with the origin where it was.
    let partFrame: SetupFrame
    /// How many shapes an "Add toolpath" tooltip would use; 0 hides the tooltip.
    /// The owner decides when it is allowed (e.g. not while a toolpath is open).
    let addToolpathShapeCount: Int
    /// 3D mode: the selected STEP edges can become a toolpath (false while a toolpath is open).
    let canAddToolpathFromEdges: Bool
    let onAddToolpath: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    init(canvasState: D2_CanvasState,
         zoomModel: CanvasZoomModel,
         mode: CAMCanvasMode = .design2D,
         stepScene: STEPDocumentScene? = nil,
         partFrame: SetupFrame = .identity,
         addToolpathShapeCount: Int = 0,
         canAddToolpathFromEdges: Bool = false,
         onAddToolpath: @escaping () -> Void = {}) {
        _scene = StateObject(wrappedValue: CAMSceneModel(canvasState: canvasState))
        self.zoomModel = zoomModel
        self.mode = mode
        self.stepScene = stepScene
        self.partFrame = partFrame
        self.addToolpathShapeCount = addToolpathShapeCount
        self.canAddToolpathFromEdges = canAddToolpathFromEdges
        self.onAddToolpath = onAddToolpath
    }

    var body: some View {
        Group {
            switch mode {
            case .design2D:
                canvas2D
            case .step3D:
                canvas3D
            }
        }
        .onAppear {
            scene.setColorScheme(colorScheme)
        }
        .onChange(of: colorScheme) { _, newScheme in
            scene.setColorScheme(newScheme)
        }
    }

    private var canvas2D: some View {
        MetalCanvasView(objects: .constant(scene.renderObjects),
                        interactionMode: .locked2D,
                        clearColor: scene.backgroundColor,
                        pointerHandler: scene.interaction,
                        zoomModel: zoomModel)
            .overlay {
                AddToolpathTooltipLayer(scene: scene,
                                        zoomModel: zoomModel,
                                        shapeCount: addToolpathShapeCount,
                                        onAdd: onAddToolpath)
            }
    }

    /// The same scene as 2D (shapes, toolpaths, stock, selection overlays, same
    /// background), seen through the free 3D camera, plus the STEP wireframe when
    /// there is one. The ruler sits on the stock's bottom face here, and the XYZ
    /// origin axes are drawn (see `CAMSceneModel.renderObjects3D`).
    /// A different branch than 2D means a fresh `MetalCanvasView`: it reads its
    /// interaction mode once, when it is created. `scene` lives in this
    /// view, so coming back to 2D loses nothing.
    @ViewBuilder
    private var canvas3D: some View {
        if let stepScene {
            STEP3DCanvas(scene: stepScene, sceneObjects: scene.renderObjects3D(frame: partFrame),
                         partTransform: partFrame.matrix,
                         previewTransform: partFrame.previewMatrix,
                         clearColor: scene.backgroundColor, isDark: colorScheme == .dark,
                         zoomModel: zoomModel,
                         canAddToolpath: canAddToolpathFromEdges, onAddToolpath: onAddToolpath)
        } else {
            MetalCanvasView(objects: .constant(scene.renderObjects3D(frame: partFrame)),
                            interactionMode: .free3D,
                            clearColor: scene.backgroundColor,
                            zoomModel: zoomModel,
                            partTransform: partFrame.matrix,
                            previewTransform: partFrame.previewMatrix,
                            adaptiveModelFit: true)
        }
    }
}

/// The CAM scene plus the STEP wireframe in one free 3D canvas: orbit, pan, zoom
/// and the orientation cube from `CanvasInputSettings`, and edge picking.
private struct STEP3DCanvas: View {

    @ObservedObject var scene: STEPDocumentScene
    let sceneObjects: [RenderObject]
    let partTransform: simd_float4x4
    let previewTransform: simd_float4x4
    let clearColor: SIMD4<Float>
    let isDark: Bool
    let zoomModel: CanvasZoomModel
    let canAddToolpath: Bool
    let onAddToolpath: () -> Void

    var body: some View {
        MetalCanvasView(objects: .constant(sceneObjects + scene.visibleObjects),
                        interactionMode: .free3D,
                        clearColor: clearColor,
                        zoomModel: zoomModel,
                        on3DClick: { point, size, matrix, modifiers in
                            scene.pick(point: point, viewport: size, matrix: matrix,
                                       extend: modifiers.contains(.shift) || modifiers.contains(.command))
                        },
                        partTransform: partTransform,
                        previewTransform: previewTransform,
                        adaptiveModelFit: true,
                        fitRequest: scene.fitRequest)
            .id(ObjectIdentifier(scene))
            .onAppear { scene.setAppearance(isDark: isDark) }
            .onChange(of: isDark) { _, dark in scene.setAppearance(isDark: dark) }
            .overlay {
                if canAddToolpath {
                    STEPAddToolpathTooltipLayer(scene: scene, zoomModel: zoomModel, onAdd: onAddToolpath)
                }
            }
    }
}

/// The "Add toolpath" tooltip of the 2D canvas, over the selected STEP edges. It follows the
/// selection's top as the camera orbits, pans and zooms.
private struct STEPAddToolpathTooltipLayer: View {

    @ObservedObject var scene: STEPDocumentScene
    let zoomModel: CanvasZoomModel
    let onAdd: () -> Void

    @State private var frameTick = 0

    private static let gap: CGFloat = 6
    private static let minAnchorY: CGFloat = 56
    private static let horizontalMargin: CGFloat = 110

    var body: some View {
        let _ = frameTick
        GeometryReader { proxy in
            let count = scene.selectedEdges.count
            if count > 0, let anchor = anchor(in: proxy.size) {
                AddToolpathTooltip(shapeCount: count, noun: "edge", onAdd: onAdd)
                    .fixedSize()
                    .frame(width: 0, height: 0, alignment: .bottom)
                    .position(anchor)
                    .transition(.opacity)
            }
        }
        .onReceive(zoomModel.frameRendered.receive(on: DispatchQueue.main)) { _ in
            frameTick &+= 1
        }
    }

    /// The highest point of the selection's bounding box on screen, centered horizontally on it.
    private func anchor(in size: CGSize) -> CGPoint? {
        guard let box = scene.selectionBox, size.width > 0, size.height > 0 else {
            return nil
        }
        var projected: [CGPoint] = []
        for x in [box.min.x, box.max.x] {
            for y in [box.min.y, box.max.y] {
                for z in [box.min.z, box.max.z] {
                    if let point = zoomModel.normalizedViewPoint(forWorld: SIMD3<Float>(x, y, z)) {
                        projected.append(point)
                    }
                }
            }
        }
        guard let top = projected.map(\.y).min(),
              let left = projected.map(\.x).min(),
              let right = projected.map(\.x).max() else {
            return nil
        }
        let margin = min(Self.horizontalMargin, size.width / 2)
        let x = min(max((left + right) / 2 * size.width, margin), size.width - margin)
        let y = max(top * size.height - Self.gap, Self.minAnchorY)
        return CGPoint(x: x, y: y)
    }
}

/// Covers the canvas and keeps an "Add toolpath" tooltip on top of the selected
/// shapes, arrow pointing down at them. It follows the shapes through pan, zoom
/// and resize by re-reading the camera after every frame the canvas draws.
private struct AddToolpathTooltipLayer: View {

    @ObservedObject var scene: CAMSceneModel
    let zoomModel: CanvasZoomModel
    let shapeCount: Int
    let onAdd: () -> Void

    /// Bumped after every frame so the body re-reads the camera. Only this
    /// small view is invalidated, not the CAM screen around it.
    @State private var frameTick = 0

    /// Space between the arrow tip and the top of the shape.
    private static let gap: CGFloat = 6
    /// Keeps the tooltip on screen when the shape is at (or above) the top
    /// edge: roughly its own height plus a margin.
    private static let minAnchorY: CGFloat = 56
    private static let horizontalMargin: CGFloat = 110

    var body: some View {
        let _ = frameTick
        GeometryReader { proxy in
            if shapeCount > 0, let anchor = anchor(in: proxy.size) {
                AddToolpathTooltip(shapeCount: shapeCount, onAdd: onAdd)
                    .fixedSize()
                    // Zero-size frame bottom-aligned on the anchor: the
                    // tooltip's arrow tip lands exactly on that point.
                    .frame(width: 0, height: 0, alignment: .bottom)
                    .position(anchor)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: shapeCount > 0)
        .onReceive(zoomModel.frameRendered.receive(on: DispatchQueue.main)) { _ in
            frameTick &+= 1
        }
    }

    /// Top-center of the selection's bounding box, in this view's points.
    private func anchor(in size: CGSize) -> CGPoint? {
        guard let bounds = scene.selectionWorldBounds,
              let top = zoomModel.normalizedViewPoint(forWorld: CGPoint(x: bounds.midX, y: bounds.maxY)),
              size.width > 0, size.height > 0 else {
            return nil
        }
        let margin = min(Self.horizontalMargin, size.width / 2)
        let x = min(max(top.x * size.width, margin), size.width - margin)
        let y = max(top.y * size.height - Self.gap, Self.minAnchorY)
        return CGPoint(x: x, y: y)
    }
}

private struct AddToolpathTooltip: View {

    let shapeCount: Int
    var noun = "shape"
    let onAdd: () -> Void

    private static let arrowSize = CGSize(width: 16, height: 8)

    var body: some View {
        HStack(spacing: 12) {
            Text(shapeCount == 1 ? "1 \(noun) selected" : "\(shapeCount) \(noun)s selected")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(action: onAdd) {
                Label("Add toolpath", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 8 + Self.arrowSize.height)
        .background {
            CalloutShape(arrowSize: Self.arrowSize)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .overlay {
            CalloutShape(arrowSize: Self.arrowSize)
                .stroke(.separator)
        }
    }
}

/// A rounded rectangle with a downward arrow centered on its bottom edge, as one
/// outline so the fill and the stroke have no seam where the arrow joins.
private struct CalloutShape: Shape {

    var cornerRadius: CGFloat = 10
    let arrowSize: CGSize

    func path(in rect: CGRect) -> Path {
        let r = cornerRadius
        let bottom = rect.maxY - arrowSize.height
        let midX = rect.midX

        var p = Path()
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                 tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r), radius: r)
        p.addLine(to: CGPoint(x: rect.maxX, y: bottom - r))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: bottom),
                 tangent2End: CGPoint(x: rect.maxX - r, y: bottom), radius: r)
        // The arrow
        p.addLine(to: CGPoint(x: midX + arrowSize.width / 2, y: bottom))
        p.addLine(to: CGPoint(x: midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: midX - arrowSize.width / 2, y: bottom))
        p.addLine(to: CGPoint(x: rect.minX + r, y: bottom))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: bottom),
                 tangent2End: CGPoint(x: rect.minX, y: bottom - r), radius: r)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                 tangent2End: CGPoint(x: rect.minX + r, y: rect.minY), radius: r)
        p.closeSubpath()
        return p
    }
}
