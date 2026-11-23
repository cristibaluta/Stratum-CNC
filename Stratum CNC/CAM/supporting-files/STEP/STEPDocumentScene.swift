//
//  STEPDocumentScene.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.11.2026.
//

import Foundation
import simd
import StratumCAM
import SwiftSTEP

@MainActor
final class STEPDocumentScene: ObservableObject, Identifiable {
    let id: UUID
    @Published private(set) var content: STEPViewerContent
    @Published private(set) var baseObjects: [RenderObject]
    /// One lit-triangle object per body with a surface, in the same body order as `baseObjects`
    /// (`nil` where the body has none or the mode draws no faces).
    @Published private(set) var solidObjects: [RenderObject?]
    @Published private(set) var selectedEdges: Set<STEP.EdgeID> = []
    /// Bodies hidden with the eye of their row.
    @Published private(set) var userHiddenBodies: Set<STEP.BodyID> = []
    /// Bodies the active setup doesn't include: not drawn, not pickable. Session-only, set by
    /// `CAMModel.applyActivePlacement`; separate from the eye, which keeps what the person chose.
    @Published private(set) var setupExcludedBodies: Set<STEP.BodyID> = []
    /// Every body that is not drawn.
    var hiddenBodies: Set<STEP.BodyID> {
        userHiddenBodies.union(setupExcludedBodies)
    }
    /// Where each body sits on the canvas, in mm. A body's own corner (min X, min Y) and top
    /// (max Z) are at 0 in its frame, so this is the position of that corner and of its top
    /// surface. Changed through `STEPWorkspace.setPosition`.
    @Published private(set) var positions: [STEP.BodyID: SIMD3<Float>]
    @Published var isModelVisible = true {
        // Hiding the model drops a plain selection. A toolpath being edited keeps its edges.
        didSet {
            if !isModelVisible, !isPicking {
                setSelection([], notify: false)
            }
        }
    }
    /// A toolpath is open: clicks add and remove edges from it (see `STEPWorkspace.beginPicking`).
    private(set) var isPicking = false
    /// Called with the whole selection after every change made by the user while picking.
    var onSelectionChanged: ((Set<STEP.EdgeID>) -> Void)?
    /// Bounding box of the shown bodies together in canvas mm, as they sit (each one's min X/Y corner
    /// and top are at its position, see there). The tooltip is held above its top. `nil` without bounds.
    var modelBox: (min: SIMD3<Float>, max: SIMD3<Float>)? {
        var low = SIMD3<Float>(repeating: .infinity)
        var high = SIMD3<Float>(repeating: -.infinity)
        for body in content.geometry.bodies where !hiddenBodies.contains(body.id) {
            guard let size = content.size(of: body.id) else {
                continue
            }
            let origin = position(of: body.id)
            low = simd_min(low, origin + SIMD3<Float>(0, 0, -size.z))
            high = simd_max(high, origin + SIMD3<Float>(size.x, size.y, 0))
        }
        return low.x.isFinite ? (low, high) : nil
    }
    /// Bounding box of the selected edges in canvas mm, to anchor the "Add toolpath" tooltip.
    @Published private(set) var selectionBox: (min: SIMD3<Float>, max: SIMD3<Float>)?
    @Published private(set) var selectionObjects: [RenderObject] = []
    /// Draw the selected edges flattened onto the z0 plane (orange, dotted), with
    /// vertical drop lines from their endpoints. Remembered across sessions (on by default).
    @Published var showsProjection = true {
        didSet {
            guard showsProjection != oldValue else {
                return
            }
            defaults?.set(showsProjection, forKey: Self.showsProjectionKey)
            rebuildHighlight()
        }
    }
    /// Lowest and highest Z of the selected edges in the active setup's frame: their distance to the
    /// face that is up in that setup (z0), negative below it. `nil` when nothing is selected.
    @Published private(set) var selectionZRange: ClosedRange<Float>?
    @Published var fitRequest = 0

    /// Models with more triangles than this stay wireframe: lit faces need a CPU and a GPU copy
    /// of every triangle, unindexed, about 100 bytes each.
    static let defaultShadedTriangleCap = 500_000
    private static let displayModeKey = "STEPDisplayMode"
    private static let hiddenEdgeModeKey = "STEPHiddenEdgeMode"
    private static let showsProjectionKey = "STEPShowsProjection"
    private let shadedTriangleCap: Int
    private let defaults: UserDefaults?

    /// Edges behind a face: dotted (the default when the part has surfaces), not drawn, or drawn
    /// solid like a plain wireframe. Remembered across sessions, for models that have surfaces.
    /// Only the base objects are rebuilt, never the selection.
    /// Picking stays all-edges in every mode that shows edges, and the selection highlight is drawn
    /// over the whole part, hidden edges included, so a selected rear edge can always be seen.
    @Published var hiddenEdgeMode: STEPHiddenEdgeMode = .solid {
        didSet {
            guard hiddenEdgeMode != oldValue else {
                return
            }
            defaults?.set(hiddenEdgeMode.rawValue, forKey: Self.hiddenEdgeModeKey)
            rebuildObjects()
        }
    }

    /// Wireframe, shaded, or shaded with edges. Remembered across sessions; shaded with edges is the
    /// default. Setting a shaded mode on a model that cannot be shaded (`canShade`) is ignored.
    @Published var displayMode: STEPDisplayMode = .wireframe {
        didSet {
            guard displayMode != oldValue else {
                return
            }
            if displayMode != .wireframe, !canShade {
                displayMode = .wireframe
                return
            }
            defaults?.set(displayMode.rawValue, forKey: Self.displayModeKey)
            // Edges are not drawn, so a plain selection has nothing to show. A toolpath being edited keeps its edges.
            if displayMode == .shaded, !isPicking {
                setSelection([], notify: true)
            }
            rebuildObjects()
        }
    }

    /// At least one body has a surface, so the hidden-edge mode has an effect.
    var hasSurfaces: Bool {
        !content.surfaces.bodies.isEmpty
    }

    /// Shaded modes are available: surfaces exist and the triangle count is within the cap.
    var canShade: Bool {
        hasSurfaces && content.surfaces.triangleCount <= shadedTriangleCap
    }

    /// Why shaded modes are unavailable, for the panel; `nil` when they are available.
    var shadedUnavailableReason: String? {
        if !hasSurfaces {
            return "Needs every face of a body to be supported; see Details."
        }
        if content.surfaces.triangleCount > shadedTriangleCap {
            return "Too many triangles to shade (\(content.surfaces.triangleCount) of \(shadedTriangleCap)); showing wireframe."
        }
        return nil
    }

    /// - Parameter positions: where each body of `content` sits on the canvas. A body without an entry
    ///   sits at the origin.
    init(content: STEPViewerContent,
         positions: [STEP.BodyID: SIMD3<Float>] = [:],
         shadedTriangleCap: Int = STEPDocumentScene.defaultShadedTriangleCap,
         defaults: UserDefaults? = .standard) {

        id = content.importID
        self.content = content
        self.positions = positions
        self.shadedTriangleCap = shadedTriangleCap
        self.defaults = defaults
        // The saved display options; without any, shaded + edges with dotted hidden edges. A model
        // with no surfaces has nothing to shade or hide edges behind: wireframe, solid edges.
        let hasSurfaces = !content.surfaces.bodies.isEmpty
        var hidden: STEPHiddenEdgeMode = .solid
        var mode: STEPDisplayMode = .wireframe

        if hasSurfaces {
            hidden = defaults?.string(forKey: Self.hiddenEdgeModeKey).flatMap(STEPHiddenEdgeMode.init(rawValue:)) ?? .dotted
            if content.surfaces.triangleCount <= shadedTriangleCap {
                mode = defaults?.string(forKey: Self.displayModeKey).flatMap(STEPDisplayMode.init(rawValue:)) ?? .shadedEdges
            }
        }
        if let stored = defaults?.object(forKey: Self.showsProjectionKey) as? Bool {
            showsProjection = stored
        }
        hiddenEdgeMode = hidden
        displayMode = mode
        let objects = Self.makeObjects(content, isDark: true, positions: positions, displayMode: mode, hiddenMode: hidden)
        baseObjects = objects.lines
        solidObjects = objects.solids
    }

    /// Where the body sits on the canvas, in mm (its corner and its top, see `positions`).
    func position(of body: STEP.BodyID) -> SIMD3<Float> {
        positions[body] ?? .zero
    }

    /// Moves one body: its edges, faces and the selection overlay are rebuilt translated.
    func setPosition(_ position: SIMD3<Float>, of body: STEP.BodyID) {
        guard content.info(of: body) != nil, positions[body] != position else {
            return
        }
        positions[body] = position
        rebuildObjects(only: body)
        rebuildHighlight()
    }

    /// Turns one body so `face` faces up (about its own corner). The edges are the same ones, so the
    /// selection stays; what depends on where they are (plane, highlight, faces) is rebuilt, and the
    /// camera frames the part again.
    func setOrientation(_ face: SetupFace, of body: STEP.BodyID) {
        guard content.info(of: body) != nil, face != content.orientation(of: body) else {
            return
        }
        content = content.updated(body, orientation: face, scale: content.scale(of: body))
        setSelection(selectedEdges, notify: false)
        rebuildObjects(only: body)
        fitRequest &+= 1
    }

    /// Scales one body (uniformly, about its corner and top, so it stays where it is).
    func setScale(_ scale: Float, of body: STEP.BodyID) {
        guard content.info(of: body) != nil, scale.isFinite, scale > 0, scale != content.scale(of: body) else {
            return
        }
        content = content.updated(body, orientation: content.orientation(of: body), scale: scale)
        setSelection(selectedEdges, notify: false)
        rebuildObjects(only: body)
    }

    /// Takes a body out of the scene for good: its edges, faces and selected edges go.
    func removeBody(_ body: STEP.BodyID) {
        guard content.info(of: body) != nil else {
            return
        }
        content = content.removing(body)
        positions.removeValue(forKey: body)
        userHiddenBodies.remove(body)
        setupExcludedBodies.remove(body)
        setSelection(selectedEdges.filter { $0.bodyID != body }, notify: true)
        rebuildObjects()
    }

    /// The bodies where they sit on the canvas, positions applied, for the project's preview picture.
    var arrangedGeometry: STEPDisplayGeometry {
        STEPDisplayGeometry(origin: content.geometry.origin, bodies: content.geometry.bodies.map { body in
            let offset = position(of: body.id)
            return STEPDisplayGeometry.Body(id: body.id, points: body.points.map { $0 + offset },
                                            edges: body.edges, origin: body.origin)
        })
    }

    /// Rebuilds the drawn objects: of one body, or of all of them. The bodies keep their order, so
    /// `baseObjects[i]` and `solidObjects[i]` stay those of `content.geometry.bodies[i]`.
    private func rebuildObjects(only body: STEP.BodyID? = nil) {
        guard let body, let index = content.geometry.bodies.firstIndex(where: { $0.id == body }),
              baseObjects.count == content.geometry.bodies.count else {
            let objects = Self.makeObjects(content, isDark: isDarkAppearance, positions: positions,
                                           displayMode: displayMode, hiddenMode: hiddenEdgeMode)
            baseObjects = objects.lines
            solidObjects = objects.solids
            return
        }
        let objects = Self.makeObjects(content, isDark: isDarkAppearance, positions: positions,
                                       displayMode: displayMode, hiddenMode: hiddenEdgeMode, only: index)
        baseObjects[index] = objects.lines[0]
        solidObjects[index] = objects.solids[0]
    }

    /// Edge color follows the canvas background: light edges on dark, dark on light.
    private static func modelColor(isDark: Bool) -> SIMD4<Float> {
        isDark ? CanvasPalette.model : SIMD4<Float>(0.12, 0.22, 0.38, 1)
    }

    /// Edges drawn over lit faces: near black reads on the mid-grey faces in both themes.
    private static let edgeOnFacesColor = SIMD4<Float>(0.063, 0.063, 0.07, 1)

    /// Neutral grey faces, the same on a light and on a dark canvas. Lit face-on (headlight, ambient
    /// 0.65, see `MetalRenderer.drawSolids`) they come out at about 0.565, the grey of a CAD viewer.
    private static let faceColor = SIMD4<Float>(0.66, 0.66, 0.66, 1)

    /// One line object per body, and for shaded modes one lit-triangle object per body that has a
    /// surface. Wireframe: the surface rides along as depth-only occluders so hidden edges can be
    /// dotted. Shaded: the faces themselves provide the depth, the lines are kept (for the camera fit
    /// and picking data) but not drawn. A body without a surface always keeps its drawn wireframe.
    /// - Parameter only: the index of the one body to build (the result then has one entry per list).
    private static func makeObjects(_ content: STEPViewerContent,
                                    isDark: Bool,
                                    positions: [STEP.BodyID: SIMD3<Float>],
                                    displayMode: STEPDisplayMode,
                                    hiddenMode: STEPHiddenEdgeMode,
                                    only: Int? = nil)
        -> (lines: [RenderObject], solids: [RenderObject?]) {
        var lines: [RenderObject] = []
        var solids: [RenderObject?] = []
        for (index, body) in content.geometry.bodies.enumerated() {
            if let only, only != index {
                continue
            }
            let offset = positions[body.id] ?? .zero
            let placement = content.placement(of: body.id)
            let points = offset == .zero ? body.points : body.points.map { $0 + offset }
            let mesh = content.surfaces.mesh(for: body.id)
            let shaded = displayMode != .wireframe && mesh != nil
            let color = shaded ? edgeOnFacesColor : modelColor(isDark: isDark)
            var line = RenderObject(role: .model, points: points, color: color, primitive: .lineList)
            var solid: RenderObject?
            if let mesh {
                let style: HiddenLineStyle = hiddenMode == .solid ? .roleDefault : (hiddenMode == .dotted ? .dotted : .omitted)
                switch displayMode {
                    case .wireframe:
                        if hiddenMode != .solid {
                            line.occluderFaces = placement.isIdentity
                                ? mesh.occluderTriangles(offset: offset)
                                : mesh.occluderTriangles(offset: .zero).map { placement.point($0) + offset }
                            line.hiddenLineStyle = style
                        }
                    case .shadedEdges:
                        line.hiddenLineStyle = style
                    case .shaded:
                        line.visibleVertexCount = 0
                }
                if displayMode != .wireframe {
                    var triangles: [SolidVertex] = []
                    triangles.reserveCapacity(mesh.indices.count)
                    for meshIndex in mesh.indices {
                        triangles.append(SolidVertex(position: placement.point(mesh.positions[Int(meshIndex)]) + offset,
                                                     normal: placement.direction(mesh.normals[Int(meshIndex)])))
                    }
                    solid = RenderObject(role: .model, points: [], color: faceColor,
                                         primitive: .lineList, solidTriangles: triangles)
                }
            }
            lines.append(line)
            solids.append(solid)
        }
        return (lines, solids)
    }

    private var isDarkAppearance = true

    /// Rebuilds the edges in the color that suits the current appearance.
    func setAppearance(isDark: Bool) {
        guard isDark != isDarkAppearance else {
            return
        }
        isDarkAppearance = isDark
        rebuildObjects()
    }

    var visibleObjects: [RenderObject] {
        guard isModelVisible else {
            return []
        }
        var objects: [RenderObject] = []
        for (index, body) in content.geometry.bodies.enumerated() where !hiddenBodies.contains(body.id) {
            if let solid = solidObjects[index] {
                objects.append(solid)
            }
            objects.append(baseObjects[index])
        }
        return objects + selectionObjects
    }

    /// The body is drawn: the model is shown and the body itself is not hidden.
    func isBodyVisible(_ id: STEP.BodyID) -> Bool {
        isModelVisible && !userHiddenBodies.contains(id)
    }

    /// Takes the bodies the active setup doesn't include off the canvas (and out of picking).
    func setExcludedBodies(_ ids: Set<STEP.BodyID>) {
        guard ids != setupExcludedBodies else {
            return
        }
        setupExcludedBodies = ids
        setSelection(selectedEdges.filter { !ids.contains($0.bodyID) }, notify: true)
        updateCanSelectLinked()
    }

    /// The eye of the body's row. When the whole model is hidden, showing a body shows the model again.
    func toggleBodyVisible(_ id: STEP.BodyID) {
        let show = !isBodyVisible(id)
        if show, !isModelVisible {
            isModelVisible = true
        }
        setBodyVisible(id, show)
    }

    func setBodyVisible(_ id: STEP.BodyID, _ visible: Bool) {
        if visible {
            userHiddenBodies.remove(id)
        } else {
            userHiddenBodies.insert(id)
            setSelection(selectedEdges.filter { $0.bodyID != id }, notify: true)
        }
        updateCanSelectLinked()
    }

    /// The edge under `point`, if any.
    func edge(at point: CGPoint, viewport: CGSize, matrix: simd_float4x4) -> STEP.EdgeID? {
        // Edges that are not drawn must not be picked either.
        guard isModelVisible, displayMode != .shaded else {
            return nil
        }
        // Every body is stored at the origin; the matrix the canvas hands over
        // sees them there, so each is moved back into place first (`offsets`).
        // With hidden edges not drawn, the edges behind a face are not pickable.
        let isVisible = hiddenEdgeMode == .hidden ? visibilityTest(viewport: viewport, matrix: matrix) : nil
        return content.geometry.hitTest(at: point, viewport: viewport, matrix: matrix,
                                        hiddenBodies: hiddenBodies, offsets: positions, isVisible: isVisible)
    }

    /// Tells whether a point of an edge (view points x, y and depth) is in front of the faces,
    /// i.e. drawn rather than hidden behind them. Edges lie on the faces, so a small depth
    /// tolerance (mm) keeps them from hiding behind their own surface. `nil` when no body has
    /// faces: its edges are then all drawn.
    private func visibilityTest(viewport: CGSize, matrix: simd_float4x4) -> ((SIMD3<Float>) -> Bool)? {
        var screen: [SIMD3<Float>] = []
        var indices: [Int] = []
        for body in content.geometry.bodies where !hiddenBodies.contains(body.id) {
            guard let mesh = content.surfaces.mesh(for: body.id) else {
                continue
            }
            // The mesh goes through the body's placement and position, like the edges in `hitTest`
            let placement = content.placement(of: body.id)
            let bodyMatrix = matrix * STEPDisplayGeometry.translation(position(of: body.id))
            let base = screen.count
            screen += STEPFacePicker.project(positions: mesh.positions.map { placement.point($0) },
                                             matrix: bodyMatrix, viewport: viewport)
            indices += mesh.indices.map { base + Int($0) }
        }
        guard !indices.isEmpty else {
            return nil
        }
        // The projection is orthographic: depth changes by this much per mm along the view.
        let perMM = simd_length(SIMD3<Float>(matrix.columns.0.z, matrix.columns.1.z, matrix.columns.2.z))
        let tolerance = 0.1 * perMM
        return { [screen, indices] point in
            guard let hit = STEPFacePicker.pickTriangle(screen: screen, indices: indices,
                                                        at: CGPoint(x: CGFloat(point.x), y: CGFloat(point.y)),
                                                        slack: 1e-4) else { return true }
            return point.z <= hit.depth + tolerance
        }
    }

    /// The edges around the flat face under `point`, if there is one: the nearest triangle of the
    /// shaded model there, the flat patch around it, and the edges along that patch's outline
    /// (see `STEPFacePicker`). Only while the faces are drawn with their edges.
    /// - Parameter chamfersOnly: only a chamfer is looked for (nothing for a flat face). A chamfer is
    ///   a thin strip, so every point on it is within the edge tolerance of one of its rails: the
    ///   click routing asks for it before the edges, or a click on it would always pick a rail.
    func faceEdges(at point: CGPoint,
                   viewport: CGSize,
                   matrix: simd_float4x4,
                   chamfersOnly: Bool = false) -> Set<STEP.EdgeID>? {
        faceHit(at: point, viewport: viewport, matrix: matrix, chamfersOnly: chamfersOnly)?.edges
    }

    /// `faceEdges` and how far the picked triangle is from the viewer (the same depth for every scene
    /// drawn with the same `matrix`), so that with several scenes on the canvas the nearest face wins.
    func faceHit(at point: CGPoint,
                 viewport: CGSize,
                 matrix: simd_float4x4,
                 chamfersOnly: Bool = false) -> (edges: Set<STEP.EdgeID>, depth: Float)? {
        guard isModelVisible, displayMode == .shadedEdges else {
            PerfLog.log("pick", "face: ignored, model visible \(isModelVisible), display mode \(displayMode.rawValue)")
            return nil
        }

        var best: (body: STEP.BodyID, positions: [SIMD3<Float>], indices: [Int], triangle: Int, depth: Float,
                   outward: SIMD3<Float>?, normals: [SIMD3<Float>])?
        for body in content.geometry.bodies where !hiddenBodies.contains(body.id) {
            guard let mesh = content.surfaces.mesh(for: body.id) else {
                continue
            }
            // The body's mesh is in the file's frame; its placement takes it to the body's own frame,
            // which `matrix` sees at the origin, so the body's position moves it into place.
            let placement = content.placement(of: body.id)
            let bodyMatrix = matrix * STEPDisplayGeometry.translation(position(of: body.id))
            let positions = mesh.positions.map { placement.isIdentity ? $0 : placement.point($0) }
            let indices = mesh.indices.map { Int($0) }
            guard let hit = STEPFacePicker.pickTriangle(positions: positions, indices: indices, at: point,
                                                        viewport: viewport, matrix: bodyMatrix),
                  hit.depth < (best?.depth ?? .infinity) else {
                continue
            }
            // The way the face looks out of the solid, from the mesh's own shading normals.
            // Used to tell bosses (walls rising off the face) from holes (walls dropping into it).
            var normal = SIMD3<Float>.zero
            for corner in 0..<3 {
                normal += placement.direction(mesh.normals[Int(indices[3 * hit.triangle + corner])])
            }
            let outward: SIMD3<Float>? = simd_length(normal) > 1e-6 ? simd_normalize(normal) : nil
            best = (body.id, positions, indices, hit.triangle, hit.depth, outward,
                    mesh.normals.map { placement.direction($0) })
        }
        guard let best else {
            PerfLog.log("pick", "face: no triangle under the cursor")
            return nil
        }
        PerfLog.log("pick", "face: triangle \(best.triangle) of body \(best.body), outward \(best.outward.map { String(format: "(%.2f, %.2f, %.2f)", $0.x, $0.y, $0.z) } ?? "unknown")")
        // A chamfer is picked through its two rails: its face is not flat when it goes round a hole.
        if let rails = STEPChamferPicker.rails(positions: best.positions, indices: best.indices,
                                               normals: best.normals, triangle: best.triangle) {
            var edges = Set<STEP.EdgeID>()
            // Partly covered edges count too: a round chamfer split by a seam is walked as halves.
            for rail in rails {
                edges.formUnion(content.geometry.edges(onBoundaryOf: rail, in: best.body, coverage: 0.35))
            }
            PerfLog.log("pick", "chamfer: \(rails.count) rail(s), \(edges.count) STEP edge(s) matched"
                        + " (boundary segments \(rails.map { $0.boundary.count }))")
            if !edges.isEmpty {
                chamferEdges.formUnion(edges)
                return (edges, best.depth)
            }
        }
        if chamfersOnly {
            return nil
        }
        guard let region = STEPFacePicker.flatRegion(positions: best.positions, indices: best.indices,
                                                     triangle: best.triangle,
                                                     outward: best.outward) else {
            PerfLog.log("pick", "face: not a flat face (no coplanar patch around the triangle)")
            return nil
        }
        let edges = content.geometry.edges(onBoundaryOf: region, in: best.body)
        PerfLog.log("pick", "face: flat, \(region.boundary.count) outline segment(s), \(edges.count) STEP edge(s) matched")
        return edges.isEmpty ? nil : (edges, best.depth)
    }

    /// A click on a face: its edges become the selection. Extending (Shift or Cmd, or the picks
    /// of an open toolpath) adds them, or takes them out again when they were all selected.
    func selectFace(_ edges: Set<STEP.EdgeID>, extend: Bool) {
        guard isModelVisible else {
            return
        }
        var selection = selectedEdges
        if extend || isPicking {
            if edges.isSubset(of: selection) {
                selection.subtract(edges)
            } else {
                selection.formUnion(edges)
            }
        } else {
            selection = edges
        }
        setSelection(selection, notify: true)
    }

    func select(_ id: STEP.EdgeID?, extend: Bool) {
        guard let id, isModelVisible, !hiddenBodies.contains(id.bodyID),
              content.geometry.bodies.contains(where: { $0.edges.contains(where: { $0.id == id }) }) else {
            // Like the 2D canvas: an empty click keeps the toolpath's shapes while picking
            if !isPicking {
                clearSelection()
            }
            return
        }
        var selection = selectedEdges
        if extend || isPicking {
            if !selection.insert(id).inserted {
                selection.remove(id)
            }
        } else {
            selection = [id]
        }
        setSelection(selection, notify: true)
    }

    func clearSelection() {
        setSelection([], notify: true)
    }

    /// The plane every selected edge lies in, if there is one (see `STEPDisplayGeometry.plane`).
    /// Kept up to date by `setSelection` so views can read it every frame without recomputing.
    private(set) var selectionPlane: STEPDisplayGeometry.Plane?
    /// Kind and size of each selected edge, for the selection details.
    private(set) var selectionMeasures: [STEPDisplayGeometry.EdgeMeasure] = []
    /// What the selected edges form (holes, a closed outline, a line, an open path).
    private(set) var selectionFeature: STEPSelectionFeature?
    /// The rails of every chamfer picked so far. A selection made only of these is a chamfer.
    private var chamferEdges = Set<STEP.EdgeID>()

    /// The operations "Add toolpath" offers for the selection, most likely first.
    var availableOperations: [SC.MachiningOperation.Kind] {
        selectionFeature.map(SC.MachiningOperation.Kind.operations(for:)) ?? []
    }

    /// "Select linked in plane" would add something: the selection lies in one plane and edges
    /// in that plane are connected to it that are not selected yet. Kept up to date by
    /// `setSelection` (and when a body is shown or hidden), so views can read it every frame.
    private(set) var canSelectLinkedInPlane = false

    private func updateCanSelectLinked() {
        guard let plane = selectionPlane, !selectedEdges.isEmpty else {
            canSelectLinkedInPlane = false
            return
        }
        canSelectLinkedInPlane = content.geometry.linkedEdges(startingFrom: selectedEdges, in: plane,
                                                              hiddenBodies: hiddenBodies) != selectedEdges
    }

    /// "Select similar" has something to work from: the selection is circles lying flat, the
    /// rims of holes.
    var canSelectSimilarHoles: Bool {
        !selectionMeasures.isEmpty && selectionMeasures.allSatisfy {
            $0.kind == .circle && abs($0.normal?.z ?? 0) > 0.9999
        }
    }

    /// Adds the holes like the selected ones: the same diameter and depth. A hole's top circle
    /// finds the other holes' top circles, so each hole is selected once.
    func selectSimilarHoles() {
        guard isModelVisible, canSelectSimilarHoles else {
            return
        }
        let similar = content.geometry.similarHoles(to: selectedEdges, hiddenBodies: hiddenBodies)
        guard !similar.isEmpty else {
            return
        }
        setSelection(selectedEdges.union(similar), notify: true)
    }

    /// Adds every edge connected to the selection that lies in the same plane, e.g. the whole
    /// outline of a face, or of a pocket floor, from one clicked edge.
    func selectLinkedEdgesInPlane() {
        guard isModelVisible, let plane = selectionPlane else {
            return
        }
        let linked = content.geometry.linkedEdges(startingFrom: selectedEdges, in: plane,
                                                  hiddenBodies: hiddenBodies)
        guard linked != selectedEdges else {
            return
        }
        setSelection(linked, notify: true)
    }

    /// Double click on an edge: the shortcut for the tooltip's buttons. Holes (selected circles
    /// lying flat) get "Select similar", anything else "Select linked". The first click of the
    /// double click has normally selected `id` already; it is only added here when it is not
    /// selected (an open toolpath's clicks toggle, so the first one may have taken it out).
    func expandSelection(from id: STEP.EdgeID) {
        guard isModelVisible, !hiddenBodies.contains(id.bodyID) else {
            return
        }
        if !selectedEdges.contains(id) {
            setSelection(isPicking ? selectedEdges.union([id]) : [id], notify: true)
        }
        if canSelectSimilarHoles {
            selectSimilarHoles()
        } else {
            selectLinkedEdgesInPlane()
        }
    }

    private func setSelection(_ edges: Set<STEP.EdgeID>, notify: Bool) {
        selectedEdges = edges
        selectionPlane = edges.isEmpty ? nil : content.geometry.plane(containing: edges)
        selectionMeasures = edges.isEmpty ? [] : content.geometry.measures(of: edges)
        selectionFeature = content.geometry.feature(of: edges, measures: selectionMeasures, plane: selectionPlane)
        if !edges.isEmpty, edges.isSubset(of: chamferEdges) {
            selectionFeature = .chamfer
        }
        updateCanSelectLinked()
        rebuildHighlight()
        if notify {
            onSelectionChanged?(edges)
        }
    }

    /// A toolpath was opened: show its edges as the selection, and from now on every click
    /// toggles an edge of that toolpath.
    func beginPicking(selection: Set<STEP.EdgeID>) {
        isPicking = true
        setSelection(selection, notify: false)
    }

    func endPicking() {
        isPicking = false
        onSelectionChanged = nil
        setSelection([], notify: false)
    }

    /// The selected edges: solid blue.
    private static let selectionColor = SIMD4<Float>(0.15, 0.45, 1.0, 1)
    /// Their projection onto z0: dotted orange.
    private static let projectionColor = CanvasPalette.modelSelection
    /// Widths and dot size are screen points, so they stay the same at any zoom
    /// (see `RenderObject.lineWidth`).
    private static let selectionLineWidth: Float = 3
    private static let selectionDash: Float = 4
    /// The vertical lines from the selected edges down to their projection.
    private static let dropLineWidth: Float = 1

    /// The active setup. Its z0 is the stock face that is up in that setup: the part's top for the
    /// top setup, the underside for the bottom, a side of the stock for the front, back, left and
    /// right. The edges are drawn in the part's frame and turned with it, so the projection is
    /// flattened onto that face along the setup's up direction (`SetupFrame.projectOntoFace`), and
    /// the Z shown is the distance to it, never onto or from the part's own top.
    private(set) var projectionFrame: SetupFrame = .identity

    func setProjectionFrame(_ frame: SetupFrame) {
        guard frame != projectionFrame else {
            return
        }
        projectionFrame = frame
        rebuildHighlight()
    }

    private func rebuildHighlight() {
        let frame = projectionFrame
        var points: [SIMD3<Float>] = []
        var projected: [SIMD3<Float>] = []   // the edges flattened onto z0
        var drops: [SIMD3<Float>] = []       // pairs: edge endpoint, same x/y at z0
        var dropped = Set<SIMD3<Float>>()
        var zMin = Float.infinity, zMax = -Float.infinity
        var boxMin = SIMD3<Float>(repeating: .infinity), boxMax = SIMD3<Float>(repeating: -.infinity)

        for body in content.geometry.bodies where !hiddenBodies.contains(body.id) {
            let offset = position(of: body.id)
            for edge in body.edges where selectedEdges.contains(edge.id) {
                let edgePoints = body.points[edge.vertices].map { $0 + offset }
                points.append(contentsOf: edgePoints)
                // Distance to the setup's face along its up direction (its own Z: 0 on the face,
                // negative below it). For the top setup this is the part's Z, as before.
                let depths = edgePoints.map { frame.depth(of: $0) }
                let edgeMin = depths.min() ?? 0
                let edgeMax = depths.max() ?? 0
                zMin = min(zMin, edgeMin)
                zMax = max(zMax, edgeMax)
                for point in edgePoints {
                    boxMin = simd_min(boxMin, point)
                    boxMax = simd_max(boxMax, point)
                }

                // An edge that already lies on the face is its own projection.
                guard max(abs(edgeMin), abs(edgeMax)) > 1e-4 else {
                    continue
                }
                projected.append(contentsOf: edgePoints.map { frame.projectOntoFace($0) })
                if let first = edgePoints.first, let last = edgePoints.last {
                    for end in (first == last ? [first] : [first, last])
                    where abs(frame.depth(of: end)) > 1e-4 && dropped.insert(end).inserted {
                        drops.append(end)
                        drops.append(frame.projectOntoFace(end))
                    }
                }
            }
        }

        // New small overlay buffers, never new identities for the base objects.
        // The projection goes last, over the selection: seen from the top the selected edges lie
        // exactly under it, and its dots leave the blue showing in the gaps.
        var objects: [RenderObject] = []
        if !points.isEmpty {
            objects.append(RenderObject(role: .modelSelection, points: points,
                                        color: Self.selectionColor, primitive: .lineList,
                                        lineWidth: Self.selectionLineWidth))
        }
        if showsProjection {
            // The flattened edges, thick; the drop lines from the selection down to them, thin.
            for (line, width) in [(projected, Self.selectionLineWidth), (drops, Self.dropLineWidth)] where !line.isEmpty {
                objects.append(RenderObject(role: .modelSelection, points: line,
                                            color: Self.projectionColor, primitive: .lineList,
                                            isDashed: true, dashLength: Self.selectionDash,
                                            lineWidth: width))
            }
        }
        selectionObjects = objects
        selectionZRange = points.isEmpty ? nil : zMin...zMax
        selectionBox = points.isEmpty ? nil : (boxMin, boxMax)
    }
}
