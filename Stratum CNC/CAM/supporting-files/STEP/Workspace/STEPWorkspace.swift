import Foundation
import Combine
import simd
import SwiftSTEP
import StratumCAM

struct STEPSourceReference: Identifiable, Sendable {
    let id: UUID
    let name: String
    let url: URL
}

/// One body of a STEP file, as the objects list shows it.
struct STEPBodyInfo: Sendable, Identifiable {
    let id: STEP.BodyID
    /// 1-based, in the file's order: "Body 2" in the objects list.
    let number: Int
    /// The occurrence path and name the file gives the body (`Gearbox / Shaft / Die`); `nil` when it has none.
    let label: String?
    /// Where the body sits, relative to the whole file's corner (min X, min Y) and top (max Z), when
    /// nothing has been moved: the arrangement the file describes.
    let defaultPosition: SIMD3<Float>
}

/// What the user did to one body of a file, saved with the project (see `AssetData.stepBodies`).
/// Everything is optional: a body nobody touched has no state at all.
struct STEPBodyState: Codable, Hashable, Sendable {
    /// Where the body's corner and top sit on the canvas: x, y and z in mm.
    var position: [Double]?
    /// `SetupFace.persistedName`; `nil` is the top.
    var face: String?
    /// Uniform scale; `nil` is 1.
    var scale: Double?
    /// The body was deleted from the objects list. It stays in the file, so this is what keeps it out.
    var isRemoved: Bool?
}

extension STEP.BodyID {
    /// The key of the body's saved state: stable for the same file.
    var stateKey: String { "\(representationID).\(entityID).\(instance)" }
}

extension SetupFace {
    var persistedName: String {
        switch self {
            case .top: return "top"
            case .front: return "front"
            case .bottom: return "bottom"
            case .back: return "back"
            case .left: return "left"
            case .right: return "right"
        }
    }

    init?(persistedName: String) {
        guard let face = Self.allCases.first(where: { $0.persistedName == persistedName }) else { return nil }
        self = face
    }
}

struct STEPViewerContent: Sendable {
    let importID: UUID
    /// The bodies as read from the file, each in its own frame, before it is turned or scaled.
    private(set) var importedGeometry: STEPDisplayGeometry
    /// The bodies as they are on the canvas: each one scaled and turned so that its `orientation` faces up.
    private(set) var geometry: STEPDisplayGeometry
    /// Triangles that hide edges behind the part. A body that could not be tessellated completely has a
    /// partial mesh or none (see `diagnostics`); its edges are then drawn solid, as before.
    /// They stay in the file's frame: a body's `placement` takes them to where its `geometry` is.
    var surfaces = STEP.SurfaceModel()
    /// The bodies, in the file's order. A deleted body is gone from here.
    private(set) var infos: [STEPBodyInfo]
    /// How many bodies the file had before any was deleted: the list numbers them only when it is more than one.
    let bodyCount: Int
    let edgeCount: Int
    let skippedEdgeCount: Int
    let diagnostics: [STEP.Diagnostic]
    private(set) var orientations: [STEP.BodyID: SetupFace] = [:]
    private(set) var scales: [STEP.BodyID: Float] = [:]
    private(set) var placements: [STEP.BodyID: STEPPlacement] = [:]
    private(set) var sizes: [STEP.BodyID: SIMD3<Float>] = [:]

    init(importID: UUID, geometry: STEPDisplayGeometry, surfaces: STEP.SurfaceModel = STEP.SurfaceModel(),
         labels: [STEP.BodyID: String] = [:], edgeCount: Int = 0, skippedEdgeCount: Int = 0,
         diagnostics: [STEP.Diagnostic] = []) {
        self.importID = importID
        self.importedGeometry = geometry
        self.geometry = geometry
        self.surfaces = surfaces
        self.edgeCount = edgeCount
        self.skippedEdgeCount = skippedEdgeCount
        self.diagnostics = diagnostics
        bodyCount = geometry.bodies.count
        var infos: [STEPBodyInfo] = []
        var placements: [STEP.BodyID: STEPPlacement] = [:]
        var sizes: [STEP.BodyID: SIMD3<Float>] = [:]
        for (index, body) in geometry.bodies.enumerated() {
            let position = SIMD3<Float>(body.origin - geometry.origin)
            infos.append(STEPBodyInfo(id: body.id, number: index + 1, label: labels[body.id], defaultPosition: position))
            // The mesh is measured from the file's origin, the edges from the body's own corner
            placements[body.id] = STEPPlacement(rotation: matrix_identity_float3x3, shift: .zero, anchor: -position)
            sizes[body.id] = Self.size(of: body)
        }
        self.infos = infos
        self.placements = placements
        self.sizes = sizes
    }

    /// An import of a file's bodies, placed in the file's coordinates (assemblies applied).
    init(assembly: STEP.Assembly) throws {
        let geometry = try STEPDisplayGeometry(bodies: assembly.bodies,
                                               origin: STEPDisplayGeometry.displayOrigin(bounds: assembly.bounds))
        var labels: [STEP.BodyID: String] = [:]
        for body in assembly.bodies {
            let parts = body.path + (body.name.map { [$0] } ?? [])
            if !parts.isEmpty { labels[body.id] = parts.joined(separator: " / ") }
        }
        self.init(importID: assembly.importID, geometry: geometry, surfaces: assembly.surfaces, labels: labels,
                  edgeCount: assembly.edgeCount, skippedEdgeCount: assembly.skippedEdgeCount,
                  diagnostics: assembly.diagnostics)
    }

    func info(of id: STEP.BodyID) -> STEPBodyInfo? { infos.first { $0.id == id } }

    /// Which face of the body faces up.
    func orientation(of id: STEP.BodyID) -> SetupFace { orientations[id] ?? .top }

    func scale(of id: STEP.BodyID) -> Float { scales[id] ?? 1 }

    func placement(of id: STEP.BodyID) -> STEPPlacement { placements[id] ?? .identity }

    /// Width (X), depth (Y) and height (Z) of the body as it sits (turned and scaled), in mm.
    /// `nil` for a body that is not in the content.
    func size(of id: STEP.BodyID) -> SIMD3<Float>? { sizes[id] }

    /// The same content with the body turned so `face` faces up, and scaled by `scale`. Always starts
    /// from the imported geometry, so turning back to `.top` at scale 1 is exact.
    func updated(_ id: STEP.BodyID, orientation face: SetupFace, scale: Float) -> STEPViewerContent {
        guard let imported = importedGeometry.bodies.first(where: { $0.id == id }),
              let bodyInfo = self.info(of: id),
              let index = geometry.bodies.firstIndex(where: { $0.id == id }) else { return self }
        var content = self
        let rotation = face.modelRotation
        var body = imported
        var shift = SIMD3<Float>.zero
        if face != .top || scale != 1 {
            let placed = imported.placed(rotation: rotation, scale: scale)
            body = placed.body
            shift = placed.shift
        }
        content.geometry.bodies[index] = body
        content.placements[id] = STEPPlacement(rotation: rotation, shift: shift,
                                               anchor: -bodyInfo.defaultPosition, scale: scale)
        content.orientations[id] = face
        content.scales[id] = scale
        content.sizes[id] = Self.size(of: body)
        return content
    }

    /// The same content without the body.
    func removing(_ id: STEP.BodyID) -> STEPViewerContent {
        var content = self
        content.importedGeometry.bodies.removeAll { $0.id == id }
        content.geometry.bodies.removeAll { $0.id == id }
        content.infos.removeAll { $0.id == id }
        content.orientations.removeValue(forKey: id)
        content.scales.removeValue(forKey: id)
        content.placements.removeValue(forKey: id)
        content.sizes.removeValue(forKey: id)
        return content
    }

    private static func size(of body: STEPDisplayGeometry.Body) -> SIMD3<Float> {
        var low = SIMD3<Float>(repeating: .infinity)
        var high = SIMD3<Float>(repeating: -.infinity)
        for point in body.points {
            low = simd_min(low, point)
            high = simd_max(high, point)
        }
        guard low.x.isFinite, high.x.isFinite else { return .zero }
        return high - low
    }

    static func load(url: URL, importID: UUID) async throws -> STEPViewerContent {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let assembly: STEP.Assembly
            if url.pathExtension.lowercased() == "stl" {
                // A mesh file: one body. STL has no edges of its own, so the library derives them
                // (creases sharper than 30° and open boundaries), which is also what the body is
                // measured and drawn from. No units either: the library's default (mm) applies.
                assembly = try await STL.loadAssembly(contentsOf: url, importID: importID,
                                                      stl: STL.Options(featureAngleDegrees: 30, smoothShading: true))
            } else {
                // `readAssembly`, not `readGeometry`: one `Body` per solid, and an assembly's parts placed.
                assembly = try STEP.readAssembly(data: Data(contentsOf: url, options: .mappedIfSafe),
                                                 importID: importID)
            }
            return try STEPViewerContent(assembly: assembly)
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
    /// Where each body sits on the canvas, in mm. A body's own corner (min X, min Y) and top
    /// (max Z) are at 0 in its frame, so this is the position of that corner and of its top
    /// surface. Changed through `STEPWorkspace.setPosition`.
    @Published private(set) var positions: [STEP.BodyID: SIMD3<Float>]
    @Published var isModelVisible = true {
        // Hiding the model drops a plain selection. A toolpath being edited keeps its edges.
        didSet { if !isModelVisible, !isPicking { setSelection([], notify: false) } }
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
            guard let size = content.size(of: body.id) else { continue }
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

    /// - Parameter positions: where each body of `content` sits on the canvas. A body without an entry
    ///   sits at the origin.
    init(content: STEPViewerContent, positions: [STEP.BodyID: SIMD3<Float>] = [:],
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
    func position(of body: STEP.BodyID) -> SIMD3<Float> { positions[body] ?? .zero }

    /// Moves one body: its edges, faces and the selection overlay are rebuilt translated.
    func setPosition(_ position: SIMD3<Float>, of body: STEP.BodyID) {
        guard content.info(of: body) != nil, positions[body] != position else { return }
        positions[body] = position
        rebuildObjects(only: body)
        rebuildHighlight()
    }

    /// Turns one body so `face` faces up (about its own corner). The edges are the same ones, so the
    /// selection stays; what depends on where they are (plane, highlight, faces) is rebuilt, and the
    /// camera frames the part again.
    func setOrientation(_ face: SetupFace, of body: STEP.BodyID) {
        guard content.info(of: body) != nil, face != content.orientation(of: body) else { return }
        content = content.updated(body, orientation: face, scale: content.scale(of: body))
        setSelection(selectedEdges, notify: false)
        rebuildObjects(only: body)
        fitRequest &+= 1
    }

    /// Scales one body (uniformly, about its corner and top, so it stays where it is).
    func setScale(_ scale: Float, of body: STEP.BodyID) {
        guard content.info(of: body) != nil, scale.isFinite, scale > 0, scale != content.scale(of: body) else { return }
        content = content.updated(body, orientation: content.orientation(of: body), scale: scale)
        setSelection(selectedEdges, notify: false)
        rebuildObjects(only: body)
    }

    /// Takes a body out of the scene for good: its edges, faces and selected edges go.
    func removeBody(_ body: STEP.BodyID) {
        guard content.info(of: body) != nil else { return }
        content = content.removing(body)
        positions.removeValue(forKey: body)
        hiddenBodies.remove(body)
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
    private static func makeObjects(_ content: STEPViewerContent, isDark: Bool, positions: [STEP.BodyID: SIMD3<Float>],
                                    displayMode: STEPDisplayMode, hiddenMode: STEPHiddenEdgeMode, only: Int? = nil)
        -> (lines: [RenderObject], solids: [RenderObject?]) {
        var lines: [RenderObject] = []
        var solids: [RenderObject?] = []
        for (index, body) in content.geometry.bodies.enumerated() {
            if let only, only != index { continue }
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

    /// The body is drawn: the model is shown and the body itself is not hidden.
    func isBodyVisible(_ id: STEP.BodyID) -> Bool { isModelVisible && !hiddenBodies.contains(id) }

    /// The eye of the body's row. When the whole model is hidden, showing a body shows the model again.
    func toggleBodyVisible(_ id: STEP.BodyID) {
        let show = !isBodyVisible(id)
        if show, !isModelVisible { isModelVisible = true }
        setBodyVisible(id, show)
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
        // Edges that are not drawn must not be picked either.
        guard isModelVisible, displayMode != .shaded else { return nil }
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
            guard let mesh = content.surfaces.mesh(for: body.id) else { continue }
            // The mesh goes through the body's placement and position, like the edges in `hitTest`
            let placement = content.placement(of: body.id)
            let bodyMatrix = matrix * STEPDisplayGeometry.translation(position(of: body.id))
            let base = screen.count
            screen += STEPFacePicker.project(positions: mesh.positions.map { placement.point($0) },
                                             matrix: bodyMatrix, viewport: viewport)
            indices += mesh.indices.map { base + Int($0) }
        }
        guard !indices.isEmpty else { return nil }
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
    func faceEdges(at point: CGPoint, viewport: CGSize, matrix: simd_float4x4,
                   chamfersOnly: Bool = false) -> Set<STEP.EdgeID>? {
        guard isModelVisible, displayMode == .shadedEdges else {
            PerfLog.log("pick", "face: ignored, model visible \(isModelVisible), display mode \(displayMode.rawValue)")
            return nil
        }

        var best: (body: STEP.BodyID, positions: [SIMD3<Float>], indices: [Int], triangle: Int, depth: Float,
                   outward: SIMD3<Float>?, normals: [SIMD3<Float>])?
        for body in content.geometry.bodies where !hiddenBodies.contains(body.id) {
            guard let mesh = content.surfaces.mesh(for: body.id) else { continue }
            // The body's mesh is in the file's frame; its placement takes it to the body's own frame,
            // which `matrix` sees at the origin, so the body's position moves it into place.
            let placement = content.placement(of: body.id)
            let bodyMatrix = matrix * STEPDisplayGeometry.translation(position(of: body.id))
            let positions = mesh.positions.map { placement.isIdentity ? $0 : placement.point($0) }
            let indices = mesh.indices.map { Int($0) }
            guard let hit = STEPFacePicker.pickTriangle(positions: positions, indices: indices, at: point,
                                                        viewport: viewport, matrix: bodyMatrix),
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
            let offset = position(of: body.id)
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
    /// Where a file as a whole sat in projects saved before the bodies could be moved one by one. A body
    /// with no position of its own starts there, shifted by its place in the file's arrangement.
    private var legacyOffsets: [UUID: SIMD3<Float>] = [:]
    /// Likewise the face that faced up for a whole file: the face of every body with no saved face of its own.
    private var legacyFaces: [UUID: SetupFace] = [:]
    /// What the user did to each body of each file (`STEP.BodyID.stateKey`). Kept here, not in the scene,
    /// so a reload keeps it, and so it can be put back before a file has loaded.
    private var bodyStates: [UUID: [String: STEPBodyState]] = [:]
    /// A body of a file: what a row of the objects list stands for.
    private struct ModelKey: Hashable {
        let source: UUID
        let body: STEP.BodyID
    }
    /// The id of each body's row. Made up when the file loads and kept for as long as the workspace
    /// lives (it is never saved: a body is saved by its `stateKey`).
    private var modelIDs: [ModelKey: UUID] = [:]
    private var modelKeys: [UUID: ModelKey] = [:]
    /// Called after the user moved, turned, scaled or deleted a body, so the project can save it:
    /// the file, the body's `stateKey` and its whole state.
    var onBodyStateChanged: (@MainActor (UUID, String, STEPBodyState) -> Void)?
    /// The open toolpath's edges and where edits go; set while a toolpath is open.
    private var picking: (targets: [STEPEdgeTarget], onChange: (UUID, Set<STEP.EdgeID>) -> Void)?
    /// Called when a file has finished loading, before picking is attached: the place to fix up
    /// anything saved against the previous contents of the file (see `CAMModel.relinkSTEPTargets`).
    var onSceneLoaded: ((UUID, STEPDocumentScene) -> Void)?
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var tokens: [UUID: UUID] = [:]
    private let loader: Loader

    /// The scene of the active source, once it has finished loading.
    var activeScene: STEPDocumentScene? { activeID.flatMap { documents[$0] } }

    init(loader: @escaping Loader = { try await STEPViewerContent.load(url: $0, importID: $1) }) {
        self.loader = loader
    }

    // MARK: Models
    //
    // A "model" is what a row of the objects list stands for, and its id is a `UUID`: a body of a
    // loaded file, or the whole file while it is loading or when it failed to load (then the id is
    // the source's own). Moving, turning, scaling, hiding and deleting act on one body.

    /// A row of the objects list.
    struct ModelEntry: Identifiable {
        let id: UUID
        let sourceID: UUID
        /// `nil` for a file that has not loaded (or has no bodies): the row stands for the whole file.
        let body: STEP.BodyID?
        /// "plate.step · Body 2" for a file of several bodies, the file's name otherwise.
        let name: String
        /// What the file calls the body (occurrence path and name), for the row's tooltip.
        let detail: String?
    }

    /// The rows of the objects list: every body of every loaded file, in the file's order.
    var modelEntries: [ModelEntry] {
        var entries: [ModelEntry] = []
        for source in sources {
            guard let scene = documents[source.id], !scene.content.infos.isEmpty else {
                entries.append(ModelEntry(id: source.id, sourceID: source.id, body: nil, name: source.name, detail: nil))
                continue
            }
            let numbered = scene.content.bodyCount > 1
            for info in scene.content.infos {
                entries.append(ModelEntry(id: modelID(source: source.id, body: info.id), sourceID: source.id,
                                          body: info.id,
                                          name: numbered ? "\(source.name) · Body \(info.number)" : source.name,
                                          detail: info.label))
            }
        }
        return entries
    }

    private func modelID(source: UUID, body: STEP.BodyID) -> UUID {
        let key = ModelKey(source: source, body: body)
        if let id = modelIDs[key] { return id }
        let id = UUID()
        modelIDs[key] = id
        modelKeys[id] = key
        return id
    }

    /// The body a row stands for; `nil` for the row of a file that has not loaded.
    func body(ofModel id: UUID) -> STEP.BodyID? { modelKeys[id]?.body }

    /// The file a row belongs to; `nil` for an id that is not a model.
    func sourceID(ofModel id: UUID) -> UUID? {
        if let key = modelKeys[id] { return key.source }
        return sources.contains(where: { $0.id == id }) ? id : nil
    }

    /// How many bodies the file still shows; 0 while it has not loaded.
    func remainingBodies(inSource id: UUID) -> Int { documents[id]?.content.infos.count ?? 0 }

    /// A row was clicked: it is the selected model, and its file is the one on the canvas.
    func select(model id: UUID) {
        selectedModelID = id
        if let source = sourceID(ofModel: id) { activeID = source }
    }

    private func resolve(_ model: UUID) -> (key: ModelKey, scene: STEPDocumentScene)? {
        guard let key = modelKeys[model], let scene = documents[key.source] else { return nil }
        return (key, scene)
    }

    func isVisible(model id: UUID) -> Bool {
        if let (key, scene) = resolve(id) { return scene.isBodyVisible(key.body) }
        return documents[id]?.isModelVisible ?? true
    }

    func toggleVisibility(of id: UUID) {
        if let (key, scene) = resolve(id) {
            scene.toggleBodyVisible(key.body)
        } else {
            documents[id]?.isModelVisible.toggle()
        }
        objectWillChange.send()
    }

    /// Where the body's corner and top sit on the canvas, in mm.
    func position(of id: UUID) -> SIMD3<Float> {
        guard let (key, scene) = resolve(id) else { return .zero }
        return scene.position(of: key.body)
    }

    /// Which face of the body faces up; `nil` for a model that is not loaded.
    func orientation(of id: UUID) -> SetupFace? {
        guard let (key, scene) = resolve(id) else { return nil }
        return scene.content.orientation(of: key.body)
    }

    /// Puts what the project saved back before the file loads. Not a user edit.
    func restoreBodyStates(_ states: [String: STEPBodyState], for source: UUID) {
        bodyStates[source] = states
    }

    /// Puts the saved position of a whole file back before it loads (see `legacyOffsets`). Not a user edit.
    func restoreLegacyOffset(_ offset: SIMD3<Float>, for source: UUID) {
        legacyOffsets[source] = offset
    }

    /// Puts the saved face-up of a whole file back before it loads (see `legacyFaces`). Not a user edit.
    func restoreLegacyFace(_ face: SetupFace, for source: UUID) {
        legacyFaces[source] = face
    }

    /// Records a change of one body: kept for reloads, and reported so the project saves it.
    private func update(_ key: ModelKey, _ change: (inout STEPBodyState) -> Void) {
        var state = bodyStates[key.source]?[key.body.stateKey] ?? STEPBodyState()
        change(&state)
        bodyStates[key.source, default: [:]][key.body.stateKey] = state
        onBodyStateChanged?(key.source, key.body.stateKey, state)
    }

    /// A body changed: toolpaths cut from its edges are outdated.
    private func bodyChanged() {
        objectWillChange.send()
        // TODO: who deleted this? Is it needed?
//        onModelMoved?()
    }

    func setPosition(_ position: SIMD3<Float>, for id: UUID) {
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite,
              let (key, scene) = resolve(id), position != scene.position(of: key.body) else { return }
        scene.setPosition(position, of: key.body)
        update(key) { $0.position = [Double(position.x), Double(position.y), Double(position.z)] }
        bodyChanged()
    }

    /// The user picked which face of the body faces up. Toolpaths cut from its edges are outdated.
    func setOrientation(_ face: SetupFace, for id: UUID) {
        guard let (key, scene) = resolve(id), face != scene.content.orientation(of: key.body) else { return }
        scene.setOrientation(face, of: key.body)
        // Saved even for the top: a body that was put back must not take the file's old face again
        update(key) { $0.face = face.persistedName }
        bodyChanged()
    }

    /// Scales the body about its corner and top, to this width (X, as it sits). Depth and height follow.
    func setWidth(_ width: Float, for id: UUID) {
        guard width.isFinite, width > 0, let (key, scene) = resolve(id),
              let size = scene.content.size(of: key.body), size.x > 1e-6 else { return }
        setScale(scene.content.scale(of: key.body) * width / size.x, for: id)
    }

    /// Scales the body by `factor` (×2 is 2, ÷2 is -2), like the 2D objects.
    func scaleModel(_ id: UUID, factor: Int) {
        guard factor != 0, let (key, scene) = resolve(id) else { return }
        let by = factor > 0 ? Float(factor) : 1 / Float(-factor)
        setScale(scene.content.scale(of: key.body) * by, for: id)
    }

    private func setScale(_ scale: Float, for id: UUID) {
        guard scale.isFinite, let (key, scene) = resolve(id) else { return }
        let clamped = min(max(scale, 0.001), 1000)
        guard clamped != scene.content.scale(of: key.body) else { return }
        scene.setScale(clamped, of: key.body)
        update(key) { $0.scale = clamped == 1 ? nil : Double(clamped) }
        bodyChanged()
    }

    /// Takes one body out of its file's scene. Its state remembers it as deleted, so it stays out after
    /// a reload (the file itself is not touched). The last body of a file is not removed here: the project
    /// removes the whole source (`ProjectModel.removeSTEPModel`).
    func removeBody(model id: UUID) {
        guard let (key, scene) = resolve(id), scene.content.infos.count > 1 else { return }
        scene.removeBody(key.body)
        update(key) { $0.isRemoved = true }
        modelKeys.removeValue(forKey: id)
        modelIDs.removeValue(forKey: key)
        if selectedModelID == id { selectedModelID = nil }
        bodyChanged()
    }

    /// The scene of a file that has loaded: its bodies turned, scaled and removed as the project saved them,
    /// and each one where it was left, or where the file's arrangement puts it.
    private func makeScene(for source: UUID, content loaded: STEPViewerContent) -> STEPDocumentScene {
        var content = loaded
        let states = bodyStates[source] ?? [:]
        let legacy = legacyOffsets[source] ?? .zero
        let legacyFace = legacyFaces[source] ?? .top
        var positions: [STEP.BodyID: SIMD3<Float>] = [:]
        for info in loaded.infos {
            let state = states[info.id.stateKey]
            if state?.isRemoved == true {
                content = content.removing(info.id)
                continue
            }
            var face = legacyFace
            if let name = state?.face, let saved = SetupFace(persistedName: name) { face = saved }
            var scale: Float = 1
            if let saved = state?.scale, saved.isFinite, saved > 0 { scale = Float(saved) }
            if face != .top || scale != 1 {
                content = content.updated(info.id, orientation: face, scale: scale)
            }
            if let saved = state?.position, saved.count == 3 {
                positions[info.id] = SIMD3<Float>(Float(saved[0]), Float(saved[1]), Float(saved[2]))
            } else {
                positions[info.id] = info.defaultPosition + legacy
            }
        }
        for info in content.infos { _ = modelID(source: source, body: info.id) }
        return STEPDocumentScene(content: content, positions: positions)
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
                let scene = self.makeScene(for: source.id, content: content)
                self.documents[source.id] = scene
                self.onSceneLoaded?(source.id, scene)
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
        lines.append("  \(content.infos.count) bod\(content.infos.count == 1 ? "y" : "ies") · "
                     + "\(content.edgeCount) edges shown · \(content.skippedEdgeCount) skipped")
        for info in content.infos {
            guard let size = content.size(of: info.id) else { continue }
            lines.append(String(format: "  Body %d: %g × %g × %g mm", info.number, size.x, size.y, size.z)
                         + (info.label.map { " (\($0))" } ?? ""))
        }
        let surfaces = content.surfaces
        lines.append("  \(surfaces.tessellatedFaceCount) of \(surfaces.reachableFaceCount) faces · \(surfaces.triangleCount) triangles"
                     + (surfaces.failedFaceCount > 0 ? " · \(surfaces.failedFaceCount) faces failed" : ""))
        for diagnostic in content.diagnostics {
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
        if let selected = selectedModelID, sourceID(ofModel: selected) == id { selectedModelID = nil }
        legacyOffsets.removeValue(forKey: id)
        legacyFaces.removeValue(forKey: id)
        bodyStates.removeValue(forKey: id)
        for (key, model) in modelIDs.filter({ $0.key.source == id }) {
            modelIDs.removeValue(forKey: key)
            modelKeys.removeValue(forKey: model)
        }
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
        legacyOffsets.removeAll()
        legacyFaces.removeAll()
        bodyStates.removeAll()
        modelIDs.removeAll()
        modelKeys.removeAll()
        picking = nil
        selectedModelID = nil
        activeID = nil
    }

    deinit { for task in tasks.values { task.cancel() } }
}
