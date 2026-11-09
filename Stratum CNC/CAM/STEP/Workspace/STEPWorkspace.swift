import Foundation
import Combine
import simd
import SwiftSTEP

struct STEPSourceReference: Identifiable, Sendable {
    let id: UUID
    let name: String
    let url: URL
}

struct STEPViewerContent: Sendable {
    let model: STEP.EdgeModel
    /// The geometry as read from the file, before an orientation is applied.
    let importedGeometry: STEPDisplayGeometry
    /// The geometry as it sits on the canvas: `importedGeometry` turned so that `orientation` faces up.
    private(set) var geometry: STEPDisplayGeometry
    /// Triangles that hide edges behind the part. Empty when a body's faces could not all be
    /// tessellated (see `diagnostics`); that body's edges are then drawn solid, as before.
    /// They stay in the file's frame: `placement` takes them to where `geometry` is.
    var surfaces = STEP.SurfaceModel()
    /// Which face of the model faces up.
    private(set) var orientation: SetupFace = .top
    private(set) var placement = STEPPlacement.identity

    init(model: STEP.EdgeModel, geometry: STEPDisplayGeometry, surfaces: STEP.SurfaceModel = STEP.SurfaceModel()) {
        self.model = model
        self.importedGeometry = geometry
        self.geometry = geometry
        self.surfaces = surfaces
    }

    /// The same model with `face` up. Always starts from the imported geometry, so turning
    /// back to `.top` is exact.
    func oriented(_ face: SetupFace) -> STEPViewerContent {
        var content = self
        if face == .top {
            content.geometry = importedGeometry
            content.placement = .identity
        } else {
            let placed = importedGeometry.placed(rotation: face.modelRotation)
            content.geometry = placed.geometry
            content.placement = placed.placement
        }
        content.orientation = face
        return content
    }

    /// Width (X), depth (Y) and height (Z) of the model as it sits, in mm.
    var size: SIMD3<Float>? {
        guard let bounds = model.bounds else { return nil }
        let imported = SIMD3<Float>(Float(bounds.max.x - bounds.min.x),
                                    Float(bounds.max.y - bounds.min.y),
                                    Float(bounds.max.z - bounds.min.z))
        // Quarter turns only permute the sides
        let r = orientation.modelRotation
        return simd_float3x3(columns: (abs(r.columns.0), abs(r.columns.1), abs(r.columns.2))) * imported
    }

    static func load(url: URL, importID: UUID) async throws -> STEPViewerContent {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let imported = try STEP.readGeometry(data: Data(contentsOf: url, options: .mappedIfSafe),
                                                              importID: importID)
            return try STEPViewerContent(model: imported.edges,
                                         geometry: STEPDisplayGeometry(model: imported.edges),
                                         surfaces: imported.surfaces)
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            worker.cancel()
        }
    }
}

/// How edges behind a face are drawn. Needs the body's surface (`STEPViewerContent.surfaces`);
/// without one every edge is drawn solid.
enum STEPHiddenEdgeMode: String, CaseIterable, Identifiable, Sendable {
    case dotted, hidden, solid

    var id: String { rawValue }

    var label: String {
        switch self {
            case .dotted: return "Dotted"
            case .hidden: return "Hidden"
            case .solid: return "Solid"
        }
    }
}

/// What the part is drawn as. Shaded modes need the body's surface (`STEPViewerContent.surfaces`);
/// a body without one keeps its wireframe in every mode.
enum STEPDisplayMode: String, CaseIterable, Identifiable, Sendable {
    /// Edges only; hidden edges follow `STEPHiddenEdgeMode`.
    case wireframe
    /// Lit faces, no edges (and so nothing to pick until face picking exists).
    case shaded
    /// Lit faces with the edges on top; hidden edges follow `STEPHiddenEdgeMode`.
    case shadedEdges

    var id: String { rawValue }

    var label: String {
        switch self {
            case .wireframe: return "Wireframe"
            case .shaded: return "Shaded"
            case .shadedEdges: return "Shaded + edges"
        }
    }
}

@MainActor
final class STEPDocumentScene: ObservableObject, Identifiable {
    let id: UUID
    @Published private(set) var content: STEPViewerContent
    @Published private(set) var baseObjects: [RenderObject]
    /// One lit-triangle object per body with a surface, in the same body order as `baseObjects`
    /// (`nil` where the body has none or the mode draws no faces).
    @Published private(set) var solidObjects: [RenderObject?]
    @Published private(set) var selectedEdges: Set<STEP.EdgeID> = []
    @Published private(set) var hiddenBodies: Set<STEP.BodyID> = []
    /// Where the model sits on the canvas, in mm. The model's own corner (min X,
    /// min Y) and top (max Z) are at 0, so this is the position of that corner
    /// and of the top surface. Changed through `STEPWorkspace.setPosition`.
    @Published private(set) var offset: SIMD3<Float>
    @Published var isModelVisible = true {
        // Hiding the model drops a plain selection. A toolpath being edited keeps its edges.
        didSet { if !isModelVisible, !isPicking { setSelection([], notify: false) } }
    }
    /// A toolpath is open: clicks add and remove edges from it (see `STEPWorkspace.beginPicking`).
    private(set) var isPicking = false
    /// Called with the whole selection after every change made by the user while picking.
    var onSelectionChanged: ((Set<STEP.EdgeID>) -> Void)?
    /// Bounding box of the whole model in canvas mm, as it sits (its min X/Y corner and its top
    /// are at `offset`, see there). The tooltip is held above its top. `nil` without bounds.
    var modelBox: (min: SIMD3<Float>, max: SIMD3<Float>)? {
        guard let size = content.size else { return nil }
        return (offset + SIMD3<Float>(0, 0, -size.z), offset + SIMD3<Float>(size.x, size.y, 0))
    }
    /// Bounding box of the selected edges in canvas mm, to anchor the "Add toolpath" tooltip.
    @Published private(set) var selectionBox: (min: SIMD3<Float>, max: SIMD3<Float>)?
    @Published private(set) var selectionObjects: [RenderObject] = []
    /// Draw the selected edges flattened onto the z0 plane (orange, dotted), with
    /// vertical drop lines from their endpoints. Remembered across sessions (on by default).
    @Published var showsProjection = true {
        didSet {
            guard showsProjection != oldValue else { return }
            defaults?.set(showsProjection, forKey: Self.showsProjectionKey)
            rebuildHighlight()
        }
    }
    /// Lowest and highest Z of the selected edges, in display coordinates
    /// (the model's top is z0). `nil` when nothing is selected.
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
            guard hiddenEdgeMode != oldValue else { return }
            defaults?.set(hiddenEdgeMode.rawValue, forKey: Self.hiddenEdgeModeKey)
            rebuildObjects()
        }
    }

    /// Wireframe, shaded, or shaded with edges. Remembered across sessions; shaded with edges is the
    /// default. Setting a shaded mode on a model that cannot be shaded (`canShade`) is ignored.
    @Published var displayMode: STEPDisplayMode = .wireframe {
        didSet {
            guard displayMode != oldValue else { return }
            if displayMode != .wireframe, !canShade {
                displayMode = .wireframe
                return
            }
            defaults?.set(displayMode.rawValue, forKey: Self.displayModeKey)
            // Edges are not drawn, so a plain selection has nothing to show. A toolpath being edited keeps its edges.
            if displayMode == .shaded, !isPicking { setSelection([], notify: true) }
            rebuildObjects()
        }
    }

    /// At least one body has a surface, so the hidden-edge mode has an effect.
    var hasSurfaces: Bool { !content.surfaces.bodies.isEmpty }

    /// Shaded modes are available: surfaces exist and the triangle count is within the cap.
    var canShade: Bool { hasSurfaces && content.surfaces.triangleCount <= shadedTriangleCap }

    /// Why shaded modes are unavailable, for the panel; `nil` when they are available.
    var shadedUnavailableReason: String? {
        if !hasSurfaces { return "Needs every face of a body to be supported; see Details." }
        if content.surfaces.triangleCount > shadedTriangleCap {
            return "Too many triangles to shade (\(content.surfaces.triangleCount) of \(shadedTriangleCap)); showing wireframe."
        }
        return nil
    }

    init(content: STEPViewerContent, offset: SIMD3<Float> = .zero, orientation: SetupFace = .top,
         shadedTriangleCap: Int = STEPDocumentScene.defaultShadedTriangleCap,
         defaults: UserDefaults? = .standard) {
        id = content.model.importID
        let content = content.oriented(orientation)
        self.content = content
        self.offset = offset
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
        let objects = Self.makeObjects(content, isDark: true, offset: offset, displayMode: mode, hiddenMode: hidden)
        baseObjects = objects.lines
        solidObjects = objects.solids
    }

    /// Moves the model: its edges, faces and the selection overlay are rebuilt translated.
    func setOffset(_ newOffset: SIMD3<Float>) {
        guard newOffset != offset else { return }
        offset = newOffset
        rebuildObjects()
        rebuildHighlight()
    }

    /// The face of the model that faces up.
    var orientation: SetupFace { content.orientation }

    /// Turns the model so `face` faces up. The edges are the same ones, so the selection stays; what
    /// depends on where they are (plane, highlight, faces) is rebuilt, and the camera frames the part again.
    func setOrientation(_ face: SetupFace) {
        guard face != content.orientation else { return }
        content = content.oriented(face)
        setSelection(selectedEdges, notify: false)
        rebuildObjects()
        fitRequest &+= 1
    }

    private func rebuildObjects() {
        let objects = Self.makeObjects(content, isDark: isDarkAppearance, offset: offset,
                                       displayMode: displayMode, hiddenMode: hiddenEdgeMode)
        baseObjects = objects.lines
        solidObjects = objects.solids
    }

    private static func translation(_ t: SIMD3<Float>) -> simd_float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4<Float>(t.x, t.y, t.z, 1)
        return matrix
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
    private static func makeObjects(_ content: STEPViewerContent, isDark: Bool, offset: SIMD3<Float>,
                                    displayMode: STEPDisplayMode, hiddenMode: STEPHiddenEdgeMode)
        -> (lines: [RenderObject], solids: [RenderObject?]) {
        var lines: [RenderObject] = []
        var solids: [RenderObject?] = []
        for body in content.geometry.bodies {
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
                            line.occluderFaces = content.placement.isIdentity
                                ? mesh.occluderTriangles(offset: offset)
                                : mesh.occluderTriangles(offset: .zero).map { content.placement.point($0) + offset }
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
                    for index in mesh.indices {
                        let placement = content.placement
                        triangles.append(SolidVertex(position: placement.point(mesh.positions[Int(index)]) + offset,
                                                     normal: placement.direction(mesh.normals[Int(index)])))
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
        guard isDark != isDarkAppearance else { return }
        isDarkAppearance = isDark
        rebuildObjects()
    }

    var visibleObjects: [RenderObject] {
        guard isModelVisible else { return [] }
        var objects: [RenderObject] = []
        for (index, body) in content.geometry.bodies.enumerated() where !hiddenBodies.contains(body.id) {
            if let solid = solidObjects[index] { objects.append(solid) }
            objects.append(baseObjects[index])
        }
        return objects + selectionObjects
    }

    func setBodyVisible(_ id: STEP.BodyID, _ visible: Bool) {
        if visible { hiddenBodies.remove(id) } else {
            hiddenBodies.insert(id)
            setSelection(selectedEdges.filter { $0.bodyID != id }, notify: true)
        }
        updateCanSelectLinked()
    }

    /// The edge under `point`, if any.
    func edge(at point: CGPoint, viewport: CGSize, matrix: simd_float4x4) -> STEP.EdgeID? {
        // The geometry is stored at the origin; the matrix the canvas hands over
        // sees it moved, so move it back into place first.
        // Edges that are not drawn must not be picked either.
        isModelVisible && displayMode != .shaded
            ? content.geometry.hitTest(at: point, viewport: viewport, matrix: matrix * Self.translation(offset),
                                       hiddenBodies: hiddenBodies)
            : nil
    }

    /// The edges around the flat face under `point`, if there is one: the nearest triangle of the
    /// shaded model there, the flat patch around it, and the edges along that patch's outline
    /// (see `STEPFacePicker`). Only while the faces are drawn with their edges.
    func faceEdges(at point: CGPoint, viewport: CGSize, matrix: simd_float4x4) -> Set<STEP.EdgeID>? {
        guard isModelVisible, displayMode == .shadedEdges else {
            PerfLog.log("pick", "face: ignored, model visible \(isModelVisible), display mode \(displayMode.rawValue)")
            return nil
        }
        let matrix = matrix * Self.translation(offset)
        let placement = content.placement

        var best: (body: STEP.BodyID, positions: [SIMD3<Float>], indices: [Int], triangle: Int, depth: Float,
                   outward: SIMD3<Float>?, normals: [SIMD3<Float>])?
        for body in content.geometry.bodies where !hiddenBodies.contains(body.id) {
            guard let mesh = content.surfaces.mesh(for: body.id) else { continue }
            let positions = mesh.positions.map { placement.isIdentity ? $0 : placement.point($0) }
            let indices = mesh.indices.map { Int($0) }
            guard let hit = STEPFacePicker.pickTriangle(positions: positions, indices: indices, at: point,
                                                        viewport: viewport, matrix: matrix),
                  hit.depth < (best?.depth ?? .infinity) else { continue }
            // The way the face looks out of the solid, from the mesh's own shading normals.
            // Used to tell bosses (walls rising off the face) from holes (walls dropping into it).
            var normal = SIMD3<Float>.zero
            for corner in 0..<3 { normal += placement.direction(mesh.normals[Int(indices[3 * hit.triangle + corner])]) }
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
                return edges
            }
        }
        guard let region = STEPFacePicker.flatRegion(positions: best.positions, indices: best.indices,
                                                     triangle: best.triangle,
                                                     outward: best.outward) else {
            PerfLog.log("pick", "face: not a flat face (no coplanar patch around the triangle)")
            return nil
        }
        let edges = content.geometry.edges(onBoundaryOf: region, in: best.body)
        PerfLog.log("pick", "face: flat, \(region.boundary.count) outline segment(s), \(edges.count) STEP edge(s) matched")
        return edges.isEmpty ? nil : edges
    }

    /// A click on a face: its edges become the selection. Extending (Shift or Cmd, or the picks
    /// of an open toolpath) adds them, or takes them out again when they were all selected.
    func selectFace(_ edges: Set<STEP.EdgeID>, extend: Bool) {
        guard isModelVisible else { return }
        var selection = selectedEdges
        if extend || isPicking {
            if edges.isSubset(of: selection) { selection.subtract(edges) } else { selection.formUnion(edges) }
        } else {
            selection = edges
        }
        setSelection(selection, notify: true)
    }

    func select(_ id: STEP.EdgeID?, extend: Bool) {
        guard let id, isModelVisible, !hiddenBodies.contains(id.bodyID),
              content.geometry.bodies.contains(where: { $0.edges.contains(where: { $0.id == id }) }) else {
            // Like the 2D canvas: an empty click keeps the toolpath's shapes while picking
            if !isPicking { clearSelection() }
            return
        }
        var selection = selectedEdges
        if extend || isPicking {
            if !selection.insert(id).inserted { selection.remove(id) }
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
    var availableOperations: [OperationKind] {
        selectionFeature.map(OperationKind.operations(for:)) ?? []
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
        guard isModelVisible, canSelectSimilarHoles else { return }
        let similar = content.geometry.similarHoles(to: selectedEdges, hiddenBodies: hiddenBodies)
        guard !similar.isEmpty else { return }
        setSelection(selectedEdges.union(similar), notify: true)
    }

    /// Adds every edge connected to the selection that lies in the same plane, e.g. the whole
    /// outline of a face, or of a pocket floor, from one clicked edge.
    func selectLinkedEdgesInPlane() {
        guard isModelVisible, let plane = selectionPlane else { return }
        let linked = content.geometry.linkedEdges(startingFrom: selectedEdges, in: plane,
                                                  hiddenBodies: hiddenBodies)
        guard linked != selectedEdges else { return }
        setSelection(linked, notify: true)
    }

    /// Double click on an edge: the shortcut for the tooltip's buttons. Holes (selected circles
    /// lying flat) get "Select similar", anything else "Select linked". The first click of the
    /// double click has normally selected `id` already; it is only added here when it is not
    /// selected (an open toolpath's clicks toggle, so the first one may have taken it out).
    func expandSelection(from id: STEP.EdgeID) {
        guard isModelVisible, !hiddenBodies.contains(id.bodyID) else { return }
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
        if !edges.isEmpty, edges.isSubset(of: chamferEdges) { selectionFeature = .chamfer }
        updateCanSelectLinked()
        rebuildHighlight()
        if notify { onSelectionChanged?(edges) }
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

    /// Height of the active setup's z0 in the part's frame (`SetupFrame.z0InPartFrame`): 0 for the
    /// top, the stock's thickness below it for the bottom. The edges are drawn in the part's frame
    /// and turned with it, so the projection must be flattened onto this plane, not onto the
    /// part's own top, which is the face pointing down once the stock is flipped.
    private(set) var projectionZ: Float = 0

    func setProjectionZ(_ z: Float) {
        guard z != projectionZ else { return }
        projectionZ = z
        rebuildHighlight()
    }

    private func rebuildHighlight() {
        let z0 = projectionZ
        var points: [SIMD3<Float>] = []
        var projected: [SIMD3<Float>] = []   // the edges flattened onto z0
        var drops: [SIMD3<Float>] = []       // pairs: edge endpoint, same x/y at z0
        var dropped = Set<SIMD3<Float>>()
        var zMin = Float.infinity, zMax = -Float.infinity
        var boxMin = SIMD3<Float>(repeating: .infinity), boxMax = SIMD3<Float>(repeating: -.infinity)

        for body in content.geometry.bodies where !hiddenBodies.contains(body.id) {
            for edge in body.edges where selectedEdges.contains(edge.id) {
                let edgePoints = body.points[edge.vertices].map { $0 + offset }
                points.append(contentsOf: edgePoints)
                let edgeMin = edgePoints.map(\.z).min() ?? 0
                let edgeMax = edgePoints.map(\.z).max() ?? 0
                zMin = min(zMin, edgeMin)
                zMax = max(zMax, edgeMax)
                for point in edgePoints {
                    boxMin = simd_min(boxMin, point)
                    boxMax = simd_max(boxMax, point)
                }

                // An edge that already lies on z0 is its own projection.
                guard max(abs(edgeMin - z0), abs(edgeMax - z0)) > 1e-4 else { continue }
                projected.append(contentsOf: edgePoints.map { SIMD3<Float>($0.x, $0.y, z0) })
                if let first = edgePoints.first, let last = edgePoints.last {
                    for end in (first == last ? [first] : [first, last])
                    where abs(end.z - z0) > 1e-4 && dropped.insert(end).inserted {
                        drops.append(end)
                        drops.append(SIMD3<Float>(end.x, end.y, z0))
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

@MainActor
final class STEPWorkspace: ObservableObject {
    typealias Loader = @Sendable (URL, UUID) async throws -> STEPViewerContent
    @Published private(set) var sources: [STEPSourceReference] = []
    @Published private(set) var documents: [UUID: STEPDocumentScene] = [:]
    @Published private(set) var loadingIDs: Set<UUID> = []
    @Published private(set) var errors: [UUID: String] = [:]
    @Published var activeID: UUID?
    /// The model selected in the objects list, whose position the inspector edits.
    @Published var selectedModelID: UUID?
    /// Where each source sits, kept here (not in the scene) so a reload keeps it.
    private var offsets: [UUID: SIMD3<Float>] = [:]
    /// Which face of each model faces up. Kept here, like `offsets`, so a reload keeps it.
    private var orientations: [UUID: SetupFace] = [:]
    /// Called after the user turned a model, so the project can save it.
    var onOrientationChanged: (@MainActor (UUID, SetupFace) -> Void)?
    /// A model moved: toolpaths cut from its edges are outdated.
    var onModelMoved: (() -> Void)?
    /// The open toolpath's edges and where edits go; set while a toolpath is open.
    private var picking: (targets: [STEPEdgeTarget], onChange: (UUID, Set<STEP.EdgeID>) -> Void)?
    /// Called after the user moved a model, so the project can save it.
    var onOffsetChanged: (@MainActor (UUID, SIMD3<Float>) -> Void)?
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var tokens: [UUID: UUID] = [:]
    private let loader: Loader

    /// The scene of the active source, once it has finished loading.
    var activeScene: STEPDocumentScene? { activeID.flatMap { documents[$0] } }

    init(loader: @escaping Loader = { try await STEPViewerContent.load(url: $0, importID: $1) }) {
        self.loader = loader
    }

    func position(of id: UUID) -> SIMD3<Float> { offsets[id] ?? .zero }

    func orientation(of id: UUID) -> SetupFace { orientations[id] ?? .top }

    /// Puts a saved orientation back before the source loads. Not a user edit.
    func restoreOrientation(_ face: SetupFace, for id: UUID) {
        orientations[id] = face
        documents[id]?.setOrientation(face)
    }

    /// The user picked which face of the model faces up. Toolpaths cut from its edges are outdated.
    func setOrientation(_ face: SetupFace, for id: UUID) {
        guard face != orientation(of: id) else { return }
        orientations[id] = face
        documents[id]?.setOrientation(face)
        objectWillChange.send()
        onModelMoved?()
        onOrientationChanged?(id, face)
    }

    /// Puts a saved position back before the source loads. Not a user edit.
    func restorePosition(_ position: SIMD3<Float>, for id: UUID) {
        offsets[id] = position
        documents[id]?.setOffset(position)
    }

    func setPosition(_ position: SIMD3<Float>, for id: UUID) {
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite,
              position != self.position(of: id) else { return }
        offsets[id] = position
        documents[id]?.setOffset(position)
        objectWillChange.send()
        onModelMoved?()
        onOffsetChanged?(id, position)
    }

    /// A toolpath was opened: its edges become the selection of their models, and clicking an
    /// edge adds it to or removes it from the toolpath (`onChange` gets the model and its
    /// whole selection). Models that finish loading later join in.
    func beginPicking(targets: [STEPEdgeTarget], onChange: @escaping (UUID, Set<STEP.EdgeID>) -> Void) {
        endPicking()
        picking = (targets, onChange)
        for scene in documents.values { attachPicking(to: scene) }
    }

    func endPicking() {
        picking = nil
        for scene in documents.values { scene.endPicking() }
    }

    private func attachPicking(to scene: STEPDocumentScene) {
        guard let picking else { return }
        let importID = scene.id
        scene.onSelectionChanged = { ids in picking.onChange(importID, ids) }
        scene.beginPicking(selection: Set(picking.targets.filter { $0.importID == importID }.map(\.edgeID)))
    }

    func load(_ source: STEPSourceReference, onFinished: @escaping @MainActor () -> Void = {}) {
        tasks[source.id]?.cancel()
        let token = UUID()
        tokens[source.id] = token
        if !sources.contains(where: { $0.id == source.id }) { sources.append(source) }
        documents.removeValue(forKey: source.id) // invalidates selection on reload
        errors.removeValue(forKey: source.id)
        loadingIDs.insert(source.id)
        activeID = source.id
        let loader = loader
        tasks[source.id] = Task { [weak self] in
            defer { onFinished() }
            do {
                try Task.checkCancellation()
                let content = try await loader(source.url, source.id)
                try Task.checkCancellation()
                guard let self, self.tokens[source.id] == token else { return }
                let scene = STEPDocumentScene(content: content, offset: self.offsets[source.id] ?? .zero,
                                              orientation: self.orientations[source.id] ?? .top)
                self.documents[source.id] = scene
                self.attachPicking(to: scene)
                self.finish(source.id)
                Self.logImport(of: source, content: content)
            } catch {
                guard let self, self.tokens[source.id] == token else { return }
                self.errors[source.id] = error is CancellationError ? "Import cancelled" : String(describing: error)
                self.finish(source.id)
                #if DEBUG
                print("[STEP] \(source.name): \(self.errors[source.id] ?? "failed")")
                #endif
            }
        }
    }

    /// The import numbers and diagnostics that used to sit in the STEP panel's "Details":
    /// only useful when something looks wrong, so they go to the debugger console.
    private static func logImport(of source: STEPSourceReference, content: STEPViewerContent) {
        #if DEBUG
        var lines = ["[STEP] \(source.name)"]
        lines.append("  \(content.model.edges.count) edges shown · \(content.model.skippedEdgeCount) skipped")
        if let size = content.size {
            lines.append(String(format: "  %g × %g × %g mm", size.x, size.y, size.z))
        }
        let surfaces = content.surfaces
        lines.append("  \(surfaces.tessellatedFaceCount) of \(surfaces.reachableFaceCount) faces · \(surfaces.triangleCount) triangles"
                     + (surfaces.failedFaceCount > 0 ? " · \(surfaces.failedFaceCount) faces failed" : ""))
        let diagnostics = content.model.diagnostics + surfaces.diagnostics
        for diagnostic in diagnostics {
            lines.append("  " + (diagnostic.entityID.map { "#\($0): " } ?? "") + diagnostic.message)
        }
        print(lines.joined(separator: "\n"))
        #endif
    }

    private func finish(_ id: UUID) {
        loadingIDs.remove(id)
        tokens.removeValue(forKey: id)
        tasks.removeValue(forKey: id)
    }

    func reportFailure(_ source: STEPSourceReference, message: String) {
        tasks[source.id]?.cancel()
        finish(source.id)
        if !sources.contains(where: { $0.id == source.id }) { sources.append(source) }
        documents.removeValue(forKey: source.id)
        errors[source.id] = message
        activeID = source.id
    }

    func cancel(_ id: UUID) {
        tasks[id]?.cancel()
        finish(id)
        errors[id] = "Import cancelled. Retry to load the retained project source."
    }

    func remove(_ id: UUID) {
        tasks[id]?.cancel()
        finish(id)
        documents.removeValue(forKey: id)
        errors.removeValue(forKey: id)
        sources.removeAll { $0.id == id }
        offsets.removeValue(forKey: id)
        orientations.removeValue(forKey: id)
        if selectedModelID == id { selectedModelID = nil }
        if activeID == id { activeID = sources.last?.id }
    }

    func clear() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        tokens.removeAll()
        loadingIDs.removeAll()
        documents.removeAll()
        errors.removeAll()
        sources.removeAll()
        offsets.removeAll()
        orientations.removeAll()
        picking = nil
        selectedModelID = nil
        activeID = nil
    }

    deinit { for task in tasks.values { task.cancel() } }
}
