# Plan: minimal STEP edge parser for Stratum CNC

**Goal:** open a `.step` / `.stp` file and draw its B-rep **edges** as 3D lines in the existing Metal canvas. Nothing else.

**Deliberately out of scope for this phase:** faces, shading, tessellation, picking/selection, toolpath generation, healing, PMI, AP242 tessellated geometry. The design keeps the hooks they will need (stable edge IDs, edge → vertex and edge → face links) but builds none of them.

Why edges first: the existing renderer already draws 3D line lists, so there is no new GPU work. And edges are the exact geometry that CAM will later machine from (contours, holes, chamfers), so none of this code is throwaway.

---

## 1. What the sample file tells us

`square.step` (Fusion, AP214, 8.6 KB) is a 10 × 10 × 1 box:

| Entity | Count | Role |
|---|---|---|
| `EDGE_CURVE` | 12 | **The edges we draw** |
| `LINE` + `VECTOR` | 12 | Edge geometry |
| `VERTEX_POINT` → `CARTESIAN_POINT` | 8 | Edge endpoints |
| `ORIENTED_EDGE` / `EDGE_LOOP` / `ADVANCED_FACE` | 24 / 6 / 6 | Topology (each edge is used by 2 faces) |
| `MANIFOLD_SOLID_BREP` | 1 | The body |

Things this file already teaches us:

1. **Iterate `EDGE_CURVE`, not face loops.** Each edge is referenced twice by `ORIENTED_EDGE`; iterating `EDGE_CURVE` yields each edge exactly once with no de-duplication.
2. **Complex entities exist already.** Units are written as `#184=( LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MILLI.,.METRE.) );`. The parser must handle `#id=( TYPE1(...) TYPE2(...) );`.
3. **There are two length units, and only one is correct.** `#184` is millimetre; `#185` is plain metre and is only used by the density measure. The correct one is found by following `ADVANCED_BREP_SHAPE_REPRESENTATION #12` → context `#182` → `GLOBAL_UNIT_ASSIGNED_CONTEXT((#184,…))`. "First `LENGTH_UNIT` in the file" would give the wrong scale here.
4. **Reals can be written `10.` and `0.`**, booleans as `.T.`/`.F.`, unset as `$`, derived as `*`.

**Expected output for `square.step`** (use as the first golden test): 12 edges, 8 vertices, all `line`, bounding box `(0,0,0)–(10,10,1)` mm, unit scale 1.0.

---

## 2. Architecture

A self-contained module with **no AppKit/Metal/SwiftUI imports**, so it can be unit-tested headless:

```
cam/supported-files/step/
  STEPTokenizer.swift      Part 21 lexer
  STEPFile.swift           entity index + lazy parameter parsing
  STEPValue.swift          enum for parsed parameters
  STEPUnits.swift          resolve length unit → mm scale
  STEPEdgeExtractor.swift  EDGE_CURVE → [STEPEdge]
  STEPCurves.swift         per-curve-type samplers (line, circle, ellipse, B-spline, …)
  STEPEdgeImporter.swift   public entry: URL → STEPEdgeModel (async, cancellable)
```

### Public data model

```swift
struct STEPEdgeModel {
    var edges: [STEPEdge]
    var bounds: (min: SIMD3<Double>, max: SIMD3<Double>)
    var unitScaleToMM: Double              // already applied to edge points
    var diagnostics: STEPDiagnostics       // unsupported curves, warnings, counts
}

struct STEPEdge {
    let entityID: Int                      // #id of the EDGE_CURVE: stable within a file
    let kind: CurveKind                    // .line, .circle, .ellipse, .bspline, .other
    let points: [SIMD3<Double>]            // polyline, in mm
    let startVertexID: Int
    let endVertexID: Int
    // reserved for later phases: adjacent face entity IDs, circle center/radius/axis
}
```

Keeping `entityID`, the vertex IDs and the curve kind costs nothing now, and gives selection and hole detection something to build on later.

### Parser design (matters for big files)

Two passes so a 100 MB file does not become 100 MB of Swift objects:

1. **Index pass:** memory-map the file (`Data(contentsOf:options:.mappedIfSafe)`), scan the `DATA;` section once, and record for each `#id` the entity type name(s) and the byte range of its parameter text. No parameters are parsed yet. Strings (`'…'` with `''` escapes) and `/* … */` comments must be skipped correctly while scanning.
2. **Lazy pass:** parse parameters only for entities we reach, starting from `EDGE_CURVE` and following references: `VERTEX_POINT → CARTESIAN_POINT`, curve → `AXIS2_PLACEMENT_3D` → points and directions. Cache parsed values by ID.

Run it off the main actor, report progress, honour `Task` cancellation, and return partial results plus diagnostics rather than throwing on the first unsupported entity.

---

## 3. Milestones

Each milestone ends with something testable. Estimates are rough and assume a build/run/feedback loop with the app owner.

### M0 — Tokenizer + entity index (≈ 1–2 days)
- Header skip, `DATA;` … `ENDSEC;`, `#id=TYPE(...)`, complex entities `#id=(A() B(...))`, nested lists, strings with `''`, comments, enums (`.T.`), `$`, `*`, reals (`10.`, `1.E-3`), integers, entity refs.
- **Test:** `square.step` → 187+ entities indexed, `#184` parses as complex entity with types `LENGTH_UNIT`, `NAMED_UNIT`, `SI_UNIT`; `#59` → `EDGE_CURVE('',#51,#52,#27,.T.)`.

### M1 — Lines, units, extraction (≈ 2–3 days)
- `STEPUnits`: follow the shape representation's context to the length unit. Support `SI_UNIT` with prefix (`MILLI`, `CENTI`, `$`, …) and `CONVERSION_BASED_UNIT` (inch, foot). Default to mm with a diagnostic if nothing resolves.
- `EDGE_CURVE` → start/end `VERTEX_POINT` → points. For `LINE` edges the two vertices *are* the geometry; no need to evaluate the line parameterisation.
- **Test:** `square.step` → 12 edges, bbox `(0,0,0)–(10,10,1)`, scale 1.0, zero diagnostics.

### M2 — Circles and arcs (≈ 2–3 days)
- `CIRCLE(placement, radius)`: build the frame from `AXIS2_PLACEMENT_3D` (axis, ref direction, origin; Y = axis × ref).
- Arc range comes from the edge's two vertices and `EDGE_CURVE.same_sense`. When start and end vertex are the same point, it is a full circle.
- Sampling: segment count from a chord tolerance (default 0.01 mm): `n = ceil(sweep / (2·acos(1 − tol/r)))`, with a minimum number of segments per full circle.
- **Test:** synthetic STEP of a cylinder (2 circles + seam line); a part with a 90° fillet arc. Check endpoints land exactly on the vertices and the arc passes through the expected midpoint.

### M3 — The rest of the common curves (≈ 1–1.5 weeks)
In rough order of how often they appear in CAD output:
1. `TRIMMED_CURVE` (wraps another curve with parameter or point trims).
2. `SURFACE_CURVE`, `SEAM_CURVE`, `INTERSECTION_CURVE`: use `curve_3d`, ignore the pcurves for now.
3. `B_SPLINE_CURVE_WITH_KNOTS`, including the **rational complex form** `(BOUNDED_CURVE() B_SPLINE_CURVE(...) B_SPLINE_CURVE_WITH_KNOTS(...) RATIONAL_B_SPLINE_CURVE(...) ...)`. Expand knot multiplicities, evaluate with de Boor, sample adaptively by flatness.
4. `ELLIPSE`, `POLYLINE`, `COMPOSITE_CURVE`.
5. `OFFSET_CURVE_3D`, `PARABOLA`, `HYPERBOLA`: log as unsupported at first.
- **Fallback:** any curve type we can't evaluate is drawn as a straight segment between its vertices and counted in `diagnostics`, so a file always shows *something*.
- **Test:** files containing fillets and B-spline edges; check polyline endpoints match vertices within tolerance.

### M4 — Scope to real geometry and assemblies (≈ 3–5 days)
- Only draw edges reachable from a solid or shell (`MANIFOLD_SOLID_BREP`, `BREP_WITH_VOIDS`, `SHELL_BASED_SURFACE_MODEL`), so stray construction/wireframe edges don't appear.
- Walk `solid → shell → ADVANCED_FACE → bounds → EDGE_LOOP → ORIENTED_EDGE → EDGE_CURVE` and record the faces adjacent to each edge (stored, not yet used).
- Multiple bodies in one file.
- Assemblies: resolve `NEXT_ASSEMBLY_USAGE_OCCURRENCE` / `MAPPED_ITEM` and `ITEM_DEFINED_TRANSFORMATION` into a 4×4 transform applied to each instance's edges. If assemblies prove tricky, ship M1–M3 first and report "assembly transforms not applied" as a diagnostic.

### M5 — Draw it in the app (≈ 3–5 days)
- New importer path in `CAMModel`: `supportedFiles` already lists `.step`/`.stp`, but the import switch only handles `svg` and `dxf`.
- Convert `STEPEdgeModel` into one `RenderObject` with `primitive: .lineList` (each edge's polyline expanded into start/end pairs). One object per body is fine; one per edge is not (too many GPU buffers).
- Add a render role (e.g. `.model`) and a matching `CanvasLayer` so the objects list can toggle it. Fit the camera to `bounds` using the renderer's existing bounding-sphere fit.
- Note `Camera.farZ` / `viewStandoff` are fixed (±1000 mm from the target); parts larger than that will clip. Fine for now.
- **Test:** open `square.step`; a 10 × 10 × 1 wireframe appears, orbits correctly, hidden-line dashing behaves.

### M6 — Hardening on real files (open-ended, start in parallel with M3)
- Build a corpus: parts with fillets, holes, B-splines, an assembly, multiple bodies, a large (50 MB+) file. NIST publishes public STEP test models that are useful here.
- Add a debug panel/log: entity count, edge count by kind, unsupported types, parse time.
- Profile: target "100 MB file parses and shows edges without blocking the UI".

---

## 4. Testing strategy

- **Golden tests** in the app's test target: `square.step` plus small synthetic files (cylinder, fillet, B-spline), asserting edge count, kinds, bounding box and endpoint positions.
- **Invariant checks** that work on any file: every edge's first/last point equals its start/end vertex (within tolerance); no NaN or infinite coordinates; total polyline count equals `EDGE_CURVE` count (minus those excluded in M4).
- **Reference implementation:** the algorithms (tokenizer, units resolution, circle/B-spline sampling) can be prototyped in Python and run against the sample and any files you supply, to produce expected JSON for the Swift tests. The Swift code itself must be compiled and run on your side.

---

## 5. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Wrong units (the `#184` vs `#185` trap) | Resolve through the shape representation's context; log which unit was chosen |
| Arc direction/sense mistakes (`same_sense`, `ORIENTED_EDGE` flags) | Use the vertices as ground truth and test arc midpoints |
| Rational B-splines in complex-entity form | Dedicated parser path for complex entities; test with real fillet-heavy files |
| Huge files | Index-then-lazy parsing; mmap; async with cancellation |
| Unsupported curve types | Straight-segment fallback + visible diagnostics; never fail the whole import |
| Y-up files from other CAD systems | Out of scope now; later a "set orientation" step as part of setup handling |

---

## 6. What comes after (not part of this plan)

1. Faces + tessellation → shaded model and hidden-line occlusion.
2. Edge picking (screen-space distance to polylines), then face picking.
3. Selection model stored in `ToolpathData.targets` (generalise beyond `PathSelection`).
4. Edge/face → `SC.Contour` bridge for 2.5D toolpaths; hole detection from circle edges + cylinder axes.

The `STEPEdge.entityID`, vertex IDs and kind fields exist so steps 2–4 can build on this work without rewriting it.

---

## 7. Open questions

1. Should the parser live in the app target or a separate Swift package (easier to test headless)?
2. Is a Python reference implementation useful to you for generating golden files, or do you want Swift only?
3. Which real STEP files should be in the test corpus? A few parts with holes, fillets and curved edges would speed up M2–M3 considerably.
4. Do assemblies matter for the first version, or can M4's assembly transforms wait?
