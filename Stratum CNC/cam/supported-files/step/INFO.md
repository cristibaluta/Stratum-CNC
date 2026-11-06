# STEP edge parser: how to use it

Reads a `.step` / `.stp` file (ISO 10303-21, B-rep solids and shells) and returns the
**stored edges as 3D polylines in millimetres**, ready for a line-list renderer and for edge
picking. It also tessellates the faces of each body (planes, cylinders, cones, spheres, tori) so the
viewer can draw edges behind the part dotted (see "Surfaces" below). It does not heal geometry,
read assemblies or produce machining contours.

Everything lives in `cam/supported-files/step/` and depends only on Foundation and `simd`
(no UI, no renderer, no 2D importer types).

## Quick start

```swift
// Async, off the main actor, cancellable. This is what the app uses.
let model = try await STEPEdgeImporter.importFile(at: url, importID: sourceID)

// Synchronous core, for tests or when you already have the bytes.
let model = try STEPEdgeImporter.parse(data: data, importID: sourceID)

for edge in model.edges {
    print(edge.id.entityID, edge.kind, edge.points.count)   // polyline in mm
}
for note in model.diagnostics {
    print("#\(note.entityID.map(String.init) ?? "-"): \(note.message)")
}
```

## Entry points

`STEPEdgeImporter` (in `STEPEdgeImporter.swift`):

| Call | Use it for |
| --- | --- |
| `parse(data:importID:options:) throws -> STEPEdgeModel` | Synchronous parse. Call it from a background task, never the main actor. |
| `importFile(at:importID:options:) async throws -> STEPEdgeModel` | Reads the file memory-mapped on a detached task. Cancelling the calling task cancels the parse. |

Parameters:

- `importID: UUID` is stamped into every `STEPEdgeID`. **Pass the same ID when re-parsing an unchanged
  source** (for example on project reopen) so selections stay valid. It defaults to a fresh `UUID()`.
- `options: STEPImportOptions`:
  - `assumedUnitScaleToMM: Double?` (default `nil`). If a body's length unit can't be resolved the
    import fails. Setting this opts in to "assume N mm per source unit"; the assumption is recorded
    in `STEPBodyInfo.unitsAssumed` and in `diagnostics`.
  - `chordToleranceMM: Double` (default `0.01`). Maximum chord error of sampled curves. Must be finite and positive.

Inside the app the call chain is
`CAMModel` import dispatch → `STEPWorkspace.load` → `STEPViewerContent.load` (parse + build display geometry)
→ `STEPDocumentScene` (rendering, selection). See `cam/renderer-metal/STEPWorkspace.swift`.

## Output: `STEPEdgeModel`

| Field | Meaning |
| --- | --- |
| `importID` | The ID you passed in. |
| `edges: [STEPEdge]` | Extracted edges, in deterministic order (by body, then EDGE_CURVE entity ID). |
| `bodies: [STEPBodyInfo]` | One per supported body: `id`, `contextID`, `unitScaleToMM`, `unitsAssumed`. |
| `bounds: STEPBounds?` | Min/max over all emitted points, mm. `nil` when there are no edges. |
| `diagnostics: [STEPDiagnostic]` | Per-entity notes and skipped-edge reasons (`entityID?`, `message`). |
| `indexedEntityCount` | Entities found in the DATA section. |
| `reachableEdgeCount` | Distinct edges reachable from the supported bodies (not every EDGE_CURVE in the file). |
| `skippedEdgeCount` | `reachableEdgeCount - edges.count`. Each skip has a diagnostic. |

### `STEPEdge`

| Field | Meaning |
| --- | --- |
| `id: STEPEdgeID` | `importID` + `bodyID` (representation and body entity IDs) + `entityID` (the EDGE_CURVE `#id`). Stable only for the same source and import; not tied to any render object. |
| `kind` | `.line`, `.arc`, `.circle`, `.ellipse`, `.ellipticalArc`, `.polyline`, `.bspline`. |
| `points: [SIMD3<Double>]` | Polyline in **millimetres, source coordinates** (no Y-up reorientation). Always at least 2 points. `points.first` / `points.last` are exactly the scaled start/end vertex coordinates. A closed circle, ellipse or lap has first == last. |
| `startVertexID`, `endVertexID` | VERTEX_POINT entity IDs in canonical EDGE_CURVE order. |
| `adjacentFaceIDs: [Int]` | ADVANCED_FACE / FACE_SURFACE entity IDs that use the edge (sorted, de-duplicated). A seam edge used twice by one face lists it once. |
| `chordError: Double` | Distance in mm between the polyline and the true curve. A bound for circles and ellipses, a probed estimate for B-splines, `0` for lines and file polylines. |

Edges are unique per body: an edge used by two faces appears once.

## What is supported

| Geometry | Handled as |
| --- | --- |
| `LINE` | Two vertices. |
| `CIRCLE`, `ELLIPSE` | Arc or full curve from the vertices, `same_sense`, trims; sampled to the chord tolerance. |
| `POLYLINE` | Cut to the edge between its vertices; closed polylines can wrap past their seam. |
| `B_SPLINE_CURVE_WITH_KNOTS` | Simple and complex rational records; de Boor evaluation, vertex projection, adaptive sampling. |
| `TRIMMED_CURVE` | Point or parameter trims, `sense_agreement`, context angle units (circles/ellipses). |
| `SURFACE_CURVE`, `SEAM_CURVE`, `INTERSECTION_CURVE` | Unwrapped to `curve_3d`, also around a trimmed curve. |
| Bodies | `MANIFOLD_SOLID_BREP`, `BREP_WITH_VOIDS`, `SHELL_BASED_SURFACE_MODEL`, several per file, each with its own units. |
| Units | SI with prefixes, `CONVERSION_BASED_UNIT` chains (inch, foot, degree). |

Not supported (the edge is skipped with a diagnostic naming the curve, never drawn as a guessed chord):
offset curves, parabolas, hyperbolas, `COMPOSITE_CURVE`, B-splines without explicit knots (uniform,
quasi-uniform, Bézier forms), nested trimmed curves.

## Surfaces and hidden edges

```swift
let geometry = try STEPEdgeImporter.parseGeometry(data: data, importID: id)  // edges + surfaces
geometry.edges      // STEPEdgeModel, as above
geometry.surfaces   // STEPSurfaceModel
```

`STEPSurfaceModel` holds, per body whose faces were *all* tessellated, a `STEPBodyMesh`: Float positions in mm
relative to the same display origin as `STEPDisplayGeometry`, analytic per-vertex normals (outward from the material,
never averaged across a sharp edge), UInt32 indices, and a `faces` table (face entity ID, retained `STEPSurface`
descriptor, `same_sense`, triangle range). `mesh.face(ofTriangle:)` maps a triangle back to its face.

- Face boundaries are the wireframe's own sampled edge polylines, so faces and edges agree exactly. Interior points
  of curved faces lie on the true surface at the chord tolerance.
- Supported: `PLANE` (holes included), `CYLINDRICAL_SURFACE`, `CONICAL_SURFACE`, `SPHERICAL_SURFACE`,
  `TOROIDAL_SURFACE`, trimmed by their loops, in seam-edge form or as a seamless band between two loops.
- Not supported yet: B-spline and swept surfaces, faces that reach a sphere pole or cone apex, faces that wrap a torus
  tube, vertex/poly loops, `ORIENTED_FACE`. Any such face, or a boundary edge that was skipped, drops that body's
  surface (a partial occluder would hide visible edges). Diagnostics name the face; the body's edges stay solid.
- Cap: 1,000,000 triangles per import (about 150 bytes each on CPU plus GPU).

Viewer: `STEPDocumentScene.hiddenEdgeMode` (`dotted` default, `hidden`, `solid`) attaches the mesh to the body's line
object as `RenderObject.occluderFaces` with `hiddenLineStyle`. Picking stays all-edges; the selection highlight is
drawn over the whole part. Silhouettes of curved faces are not drawn. The depth bias in `MetalRenderer` is
untuned against real files.

## Errors versus diagnostics

**The call throws** (`STEPParseError`, whose `description` is the message, or `CancellationError`) for problems with the file as a whole:

- malformed or truncated Part 21, duplicate entity IDs, excessive nesting, non-finite numbers;
- an assembly (`MAPPED_ITEM`, `NEXT_ASSEMBLY_USAGE_OCCURRENCE`, `REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION`);
- an unresolvable length unit with no `assumedUnitScaleToMM`;
- invalid options.

**The call succeeds with a diagnostic** for problems with one edge: unsupported curve, vertex not on its curve, contradictory trims, ambiguous closed edge, degenerate placement, invalid B-spline data. It also reports sampling caps, when `chordError` could not be kept under the tolerance. Always check `diagnostics`; an empty `edges` array comes with one explaining why.

An empty file result is still a successful return, with `bounds == nil`.

## Sampling and tolerances

- Curves are sampled to `chordToleranceMM` (default 0.01 mm). A full circle never has fewer than 8 segments.
- Caps: 4096 segments per circle or ellipse, 20,000 points per B-spline edge. If a cap is hit, a diagnostic reports the actual error.
- Vertices are checked against their curve with a tolerance relative to the curve size (1e-4 of the largest axis or bounding diagonal). Vertices farther off than that skip the edge.
- The polyline is **display geometry**. It is not a valid machining contour.

## Rendering and picking

`STEPDisplayGeometry(model:)` (in `STEPDisplayGeometry.swift`) converts a model into render-ready data:

```swift
let geometry = try STEPDisplayGeometry(model: model)   // throws if the extent exceeds 20 km
// geometry.origin   : SIMD3<Double>, the model centre; subtract it to get the Float points
// geometry.bodies   : [Body] with `points` (disconnected start/end pairs, Float) and
//                     `edges` ([EdgeRange] mapping a vertex range back to a STEPEdgeID)

let hit: STEPEdgeID? = geometry.hitTest(at: viewPoint, viewport: size, matrix: viewProjection,
                                        hiddenBodies: hidden, tolerance: 6)
```

Picking is in view points (so Retina is handled), clips against near/far, ranks by screen distance then depth, ignores hidden bodies, and tests all edges (no face occlusion).

## Conventions and guarantees

- All coordinates are millimetres; unit scale is applied per body.
- Double precision up to the display step; `STEPDisplayGeometry` recentres before converting to Float.
- Deterministic: the same bytes and `importID` give the same edges, IDs and order.
- Every point is finite; every edge's endpoints match its source vertices.
- A STEP file is parsed with a task-confined cache. Never share a `STEPFile` or extractor across tasks. Use the static entry points above.

## File map

| File | Role |
| --- | --- |
| `STEPEdgeImporter.swift` | Public entry points. |
| `STEPDataModel.swift` | `STEPEdgeModel`, `STEPEdge`, IDs, options, diagnostics, `STEPValue`. |
| `STEPTokenizer.swift`, `STEPFile.swift` | Part 21 lexer and the lazy entity index/cache. |
| `STEPUnits.swift` | Length and plane-angle units per representation context. |
| `STEPEdgeExtractor.swift` | Body → shell → face → loop → edge traversal. |
| `STEPCurves.swift` | Curve resolution: placements, circles/ellipses, trims, polylines, edge intervals, sampling. |
| `STEPBSpline.swift` | B-spline validation, evaluation, projection, adaptive sampling. |
| `STEPDisplayGeometry.swift` | Render-ready points and screen-space hit testing. |
| `STEPSurfaces.swift` | Retained analytic surface descriptors (point, normal, inverse). |
| `STEPSlabTriangulator.swift` | Face triangulation in (u, v): slab sweep with holes and surface-placed interior points. |
| `STEPTessellator.swift` | Face/loop traversal, surface parsing, mesh output types. |

## Tests

`STEPCurveTests.swift` (Swift Testing) uses generated Part 21 fixtures: box, cylinder, arcs, trims, ellipses,
polylines, B-splines, units and failure cases. It builds files with a small in-test `StepBuilder`, so it
needs no fixture files. Real CAD exports (holes, fillets, spline edges, multi-body parts, 50 to 100 MB files)
are still to be added.