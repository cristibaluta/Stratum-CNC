# Plan: selectable STEP wireframes for Stratum CNC

## Goal and scope

Open `.step` / `.stp`, draw stored B-rep edges in a free-3D Metal view, and select individual edges, including multi-selection. Reuse the existing line-list renderer, not the old commented-out OCCT view.

**Not in the first release:** surface tessellation/shading, surface hidden-line removal, silhouettes, face picking, machining, healing, PMI, AP242 tessellated geometry or assembly transforms. Wireframes include seams and do not reproduce view-dependent silhouettes. Sampled display geometry is not automatically a valid machining contour.

The original plan described a Fusion `square.step` (AP214, 8.6 KB, 10 × 10 × 1 mm, 12 edges, 8 vertices). That file is absent from the repository, so its exact counts/IDs and bounds remain unverified. Use a generated box fixture initially.

## Architecture

Foundation-only files under `cam/supported-files/step/`, in the app target with Swift Testing regression tests:

- `STEPDataModel.swift`: values, identities, body/context metadata, millimetre bounds and diagnostics.
- `STEPTokenizer.swift`: Part 21 lexer with resource limits.
- `STEPFile.swift`: mapped Data, component byte-range index, lazy parsing/cache.
- `STEPUnits.swift`: representation-context units, including conversion-based units.
- `STEPEdgeExtractor.swift`: scoped topology traversal and supported edge extraction.
- `STEPEdgeImporter.swift`: headless parse core and async cancellable URL entry.
- Later `STEPCurves.swift`: curve sampling and parameter-interval resolution.

Do not conform to the existing 2D Importer/D2_Object API. Preserve Double precision until rendering. Store unit scale/context per body, not globally; emitted points are millimetres. Empty results have optional bounds.

Selection identity is import ID + representation/body identity + EDGE_CURVE entity ID, independent of RenderObject UUIDs. IDs are stable only for an unchanged source/import; add occurrence paths for assemblies later. Preserve vertex IDs, kind and adjacent faces. Viewer selection stays separate from PathSelection and ToolpathData.targets.

Index without building the full parameter tree; lazily parse/cache reached entities. Bound tokens, nesting, reference recursion and sampling; check cancellation during scans/traversal. Structural corruption is fatal; unsupported/broken individual edges are skipped with diagnostics. Never swallow cancellation as a geometry warning or manufacture selectable straight chords for unsupported curves.

## Step 1[done] — Tokenizer/index, context units and scoped line extraction

- Lex DATA/ENDSEC, sparse/forward refs, simple/complex records, nested lists, doubled-quote strings, comments, enums, `$`, `*`, signed integers, decimal/exponent reals and typed values such as LENGTH_MEASURE(25.4).
- Reject duplicate IDs, malformed/truncated input, excessive nesting and nonfinite numbers. Preserve string escape text; decoding STEP non-ASCII name escapes can wait. Initially support one unparameterized DATA section.
- Resolve each shape representation's GLOBAL_UNIT_ASSIGNED_CONTEXT. Support SI prefixes and recursive CONVERSION_BASED_UNIT factors (inch/foot). Ignore unrelated density units. Reject cyclic/ambiguous/invalid units; unresolved units fail unless caller explicitly supplies an assumed scale, recorded as a warning.
- Scope shape representation → MANIFOLD_SOLID_BREP / BREP_WITH_VOIDS / SHELL_BASED_SURFACE_MODEL → shells → faces → bounds → EDGE_LOOP → ORIENTED_EDGE → EDGE_CURVE. Exclude unused/construction edges. Deduplicate within each body and preserve face adjacency. Support multiple bodies/contexts.
- Reject detected assemblies rather than rendering untransformed overlapping instances. NAUO alone does not define placement.
- For LINE edges, use the two VERTEX_POINT coordinates. Unwrap SURFACE_CURVE, SEAM_CURVE and INTERSECTION_CURVE through curve_3d. Skip unsupported curves with per-edge diagnostics.
- Synchronous testable core plus async URL entry that runs off the main actor and propagates cancellation. No app import wiring yet.
- Tests: generated 10 × 10 × 1 box (12 edges, 8 vertex IDs, two adjacent faces per edge); mm/metre/inch/foot/context-specific units; complex/sparse records; unrelated edges; broken refs; unsupported curves; empty results; malformed input and cancellation.

## Step 2 [done] — Free-3D display and edge selection

- Wire CAMModel STEP import dispatch (extensions are already advertised).
- CAM_Metal_View is locked2D; add a dedicated STEP scene/free3D path without regressing 2D editing. MetalCanvasView.handleClick is currently a stub.
- Batch lineList RenderObjects per body, not edge; retain CPU segment-range → edge-ID lookup. Add model role/layer and camera fit. Address/diagnose fixed camera depth range and zoom clamps for large models.
- Screen-space picking using rendering camera/transforms, near/far clipping and fixed tolerance in view points (Retina-correct). Rank by screen distance then depth; ignore hidden layers. Use all-edges picking without face occlusion.
- Click selects, modifier-click toggles, empty click clears. Orbit/pan drags do not select. Separate highlight batch avoids rebuilding base geometry; define highlight depth behavior.
- Clear stale IDs on reload/removal; keep selection separate from machining targets. Decide source retention/reparse versus stored geometry, and test project reopen before shipping.
- Tests: display/orbit/fit, click/multi-select, zoom/orbit/Retina/overlap/hidden layers, import replacement/cancellation and project reopen.
- No surface hidden-line test: RenderObject.occluderFaces needs triangles that this phase does not produce.

## Step 3[done] — Circles, arcs and trims

- Resolve AXIS2_PLACEMENT_3D defaults; normalize/orthogonalize frames and reject degeneracy.
- Resolve edge intervals from vertices, same_sense and trims. Closed circular edges need explicit periodic/full-circle handling; coincident coordinates alone are insufficient. ORIENTED_EDGE affects loop traversal, not canonical edge direction.
- TRIMMED_CURVE supports point/parameter trims, sense agreement and parameter units (including context angular units).
- Default 0.01 mm chord tolerance with robust tiny-radius handling, minimum segments, caps and approximation diagnostics.
- Tests: cylinder, 90-degree midpoint, reversed sense, full circle, tilted/default frames, trim combinations and tiny radii.

## Step 4[done] — More curves driven by real files

- ELLIPSE/POLYLINE with edge intervals; extend wrapper combinations.
- B_SPLINE_CURVE_WITH_KNOTS including rational complex forms: validate degree/knots/multiplicities/weights and evaluate with de Boor.
- Resolve the edge's parameter interval (endpoint projection, periodic seams, direction), not the whole underlying spline. Bounded adaptive sampling across knot spans; midpoint-only flatness is insufficient.
- Add COMPOSITE_CURVE when fixtures justify it; initially skip offsets/parabolas/hyperbolas with diagnostics.
- Validate against independent CAD exports. General STEP/B-spline compatibility needs corpus-driven estimates.

## Step 5 — Assemblies (later)

Resolve representation relationships, mapped items and occurrence transforms with units in the correct coordinate spaces. Use occurrence-path IDs for independently selectable repeated parts. Test nested/repeated/mixed-unit instances against a reference viewer.

## Hardening and later work

Starts with step 1. Swift tests and generated fixtures first; add the original box, real holes/fillets/B-splines, multi-body parts, assemblies and 50–100 MB files. Profile peak memory/responsiveness; mmap alone does not bound cache or geometry expansion. Add import progress/diagnostics UI in step 2.

Invariants: finite coordinates, optional valid bounds, endpoints match scaled source vertices, deterministic order/IDs for a given import, unique edges per body, and reachable/emitted/skipped counts (not every EDGE_CURVE in the file).

Later: surfaces/hidden-line removal, face picking, analytic geometry retention, explicit machining targets and validated contour conversion. Preserve source coordinates; automatic Y-up reorientation is deferred.
