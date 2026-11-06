# Plan: selectable STEP wireframes for Stratum CNC

## Goal and scope

Open `.step` / `.stp`, draw stored B-rep edges in a free-3D Metal view, and select individual edges, including multi-selection. Reuse the existing line-list renderer, not the old commented-out OCCT view.

**Not in the first release:** surface tessellation/shading, surface hidden-line removal, silhouettes, face picking, machining, healing, PMI, AP242 tessellated geometry or assembly transforms. Wireframes include seams and do not reproduce view-dependent silhouettes. Sampled display geometry is not automatically a valid machining contour.

The original plan described a Fusion `square.step` (AP214, 8.6 KB, 10 × 10 × 1 mm, 12 edges, 8 vertices). That file is absent from the repository, so its exact counts/IDs and bounds remain unverified. Use a generated box fixture initially.

## Architecture

Display placement: the display geometry is placed like a workpiece on the canvas, not centered. The bounding-box corner (min X, min Y) sits at x0 y0 and the top (max Z) at z0, so the part extends toward +X, +Y and down to -Z like the stock. The source coordinates stay in `model.bounds`.

In the CAM screen the STEP wireframe is a 3D mode of the shared CAM canvas (same panels, ruler and theme background as 2D), with an info panel floating over the canvas.

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

## Step 4b — Fix freeform shapes not showing or selecting (bug)

Symptom: only lines and circles reliably appear; freeform/"random" shapes are missing or unselectable. Likely cause is skipped edges (and, for hidden edges, unsupported surfaces), so start from real files and the Details diagnostics.

- Collect failing files and the per-edge diagnostics; group by reason before fixing anything.
- B-spline curves without explicit knots: UNIFORM_KNOTS, QUASI_UNIFORM_KNOTS and BEZIER_CURVE forms (including complex records): generate the knot vector from degree and control-point count, then reuse the existing de Boor evaluation.
- COMPOSITE_CURVE (ordered segments with transitions), nested TRIMMED_CURVE, and SURFACE_CURVE/SEAM_CURVE/INTERSECTION_CURVE wrapping those cases.
- Vertices that miss their curve by more than the 1e-4 relative tolerance: report the actual distance, and make the tolerance proportional to model size or configurable instead of skipping silently.
- Show skipped edges in the viewer (distinct color or count in the panel) so a missing shape is never silent; never draw a guessed chord.
- Surfaces for freeform faces: B_SPLINE_SURFACE_WITH_KNOTS (incl. rational), SURFACE_OF_REVOLUTION and SURFACE_OF_LINEAR_EXTRUSION, trimmed by their loops, so these bodies get dotted hidden edges instead of losing them (shares work with step 5).
- Tests: generated fixtures per curve form plus at least two real CAD exports with splines; assert skippedEdgeCount == 0 for them.

## Step 5 [done, unverified on GPU] — Surface tessellation and dotted hidden edges

Goal: edges hidden behind the part are drawn dotted, visible edges solid, in the shared 3D canvas.

The renderer side already exists and needs no new pipeline: `RenderObject.occluderFaces` (triangle list) is drawn depth-only before the edges (pass 0, with `occluderDepthBias`/`occluderDepthBiasSlope`), and with `showHiddenLines` on, occluded line portions are redrawn dashed (`hiddenLineDashLength`). The missing piece is data: the importer extracts edges only and never builds surfaces. This step produces them.

- Tessellate ADVANCED_FACE / FACE_SURFACE per body, honoring same_sense and oriented bounds. Planar faces: triangulate the outer loop with inner loops as holes (constrained/ear-clipping, robust to non-convex loops). Analytic surfaces: CYLINDRICAL, CONICAL, SPHERICAL, TOROIDAL (periodic seams, trimmed by loops). Later: B_SPLINE_SURFACE_WITH_KNOTS and other surfaces, trimmed by their loops.
- Use the same edge sampling for face boundaries as for the wireframe, with a chord tolerance no coarser than the edges', so faces do not poke through or fall short of their own edges. Retune the depth bias against real files.
- Tessellation is the shared foundation of steps 5 to 8: one pass produces the triangle mesh used for occluders (this step), for lit solids (step 6) and for face picking (step 7). Triangles carry per-vertex normals taken from the surface (analytic normals, not averaged across sharp edges) and a triangle-range → face ID table, from the start.
- Retain analytic surface descriptors next to the mesh (plane frame, cylinder/cone axis, radius and half-angle, sphere, torus, B-spline kind) in a new `STEPSurfaces.swift`. Steps 7 and 8 need exact radii, axes and normals, not just triangles.
- All-or-nothing per body: if any face of a body is unsupported or fails, emit no occluders for that body (a partial occluder misclassifies visible edges as hidden) and report a per-body diagnostic. Skipped faces are counted like skipped edges.
- Keep face entity IDs on the triangle ranges (also groundwork for face picking later). Triangles are Float, relative to the same display origin as the edges. Add triangle-count caps, cancellation checks and memory profiling on large files (tessellation can dwarf the edge data).
- Scene/UI: attach `occluderFaces` to the model RenderObjects in `STEPDocumentScene`; add a "Hidden edges" toggle in the STEP panel (dotted / hidden / solid-as-today). Define selection-highlight depth behavior for hidden edges and whether hidden edges stay pickable (default: yes, picking stays all-edges).
- Not included: shading, silhouette edges of curved faces (view-dependent), face picking, machining use of the surfaces.
- Tests: generated box (back edges dotted from an isometric camera, front solid), box with a through hole and with a blind pocket, cylinder with seam, fillet, B-spline face, multi-body, unsupported-face fallback, z-fighting along edges, large-file memory.

## Step 6 [done, unverified on GPU] — Solid shaded faces and light

Goal: draw the part as lit solid faces, including holes and pockets, with edges on top. Depends on step 5.

- The renderer already has a lit-triangle path: `RenderObject.solidTriangles` (positions and normals), drawn by `drawSolids` with the heightmap pipeline (directional light, ambient, one base color per batch). Feed it the step 5 mesh; no new pipeline is expected, but check the shader's light model first.
- Holes and pockets only look right if the step 5 triangulation is exact: inner loops cut out of planar faces (hole openings, pocket islands), cylindrical and conical walls trimmed to their loops, floors and walls meeting without gaps. Add these as explicit acceptance fixtures, not only boxes.
- Normals: outward for every face (apply same_sense and oriented-face flags), smooth only inside a face, never across a sharp edge. Rendering is two-sided with consistent winding, so a flipped face is visible in tests rather than silently culled.
- Light: decide whether the directional light is fixed in world space or follows the camera (a headlight reads better while orbiting); expose it as a uniform; keep an ambient floor so faces turned away from the light stay readable. Keep the depth-darkening effect off (it is a stock-depth effect).
- Color and theme: one batch per body (the renderer has one color per batch); a neutral material color that works on both light and dark canvas backgrounds; selected, hovered and hidden-body colors through separate overlay batches, like the edge selection highlight.
- Edges over solids: draw the wireframe on top with a depth bias so edges do not z-fight with their own faces; occluded edges follow the step 5 setting (dotted or hidden).
- Panel: a display mode switch, Wireframe / Hidden edges dotted / Shaded / Shaded with edges, remembered across sessions. Large models fall back to wireframe above a triangle cap, with a visible note.
- Cost: build the GPU buffers once per import and per body, never per frame. Only selection overlays are rebuilt on interaction. Profile memory and frame time on 50 to 100 MB files.
- Tests: outward normals on box, cylinder, sphere and a reversed-sense face; hole and pocket fixtures show no gaps or inverted faces; light and dark theme snapshots from several camera angles; edges visible on faces; no z-fighting along edges.

## Step 7 — Face selection (later)

Goal: click a face of the shaded model to select it, with multi-selection, like edges today. Depends on steps 5 and 6.

- Face identity: import ID + body identity + ADVANCED_FACE entity ID, independent of RenderObject UUIDs, same stability rules as edges. Selection stays separate from machining targets.
- Picking: build a ray from the click with the rendering camera (Retina-correct, same inverse matrix path as edge picking), intersect it with the CPU copy of the triangles through a BVH or uniform grid, and take the nearest hit. Unlike edge picking this respects occlusion. Triangle hit → face ID through the step 5 range table.
- Edges and faces together: in shaded modes an edge wins if it is within the pixel tolerance and not behind the nearest face hit; otherwise the face wins; in wireframe mode only edges are pickable. Click selects, Shift or Command click toggles, empty click clears, orbit and pan drags never select. Optional hover highlight.
- Highlight: an overlay batch of the selected faces' triangles in the selection color with a depth offset (no rebuild of the base mesh), plus their boundary edges.
- Panel: for each selected face show its type and exact data from the retained surface descriptor (plane normal, cylinder radius and axis, area, bounds in millimetres); selected count and Clear. Hidden bodies are not pickable.
- Tests: ray hits on box faces; a face behind another face is not picked; back faces; faces seen at grazing angles; Retina scale; overlapping bodies; hidden layers; reload and removal clear stale IDs; edge versus face priority.

## Step 8 — Holes and pockets as selectable features (later)

Goal: recognize machinable features from the face topology and let the user select a hole or a pocket as one object. Depends on steps 5 to 7 (retained surface data and adjacency).

- Convexity first: classify every shared edge as convex, concave or smooth from the two adjacent face normals (adjacent face IDs are already kept per edge). Holes and pockets are concave regions.
- Holes: a cylindrical (or conical) face whose axis is parallel to the normal of the face it opens onto, covered over a full turn (one face or two half faces), with a closed circular entry loop. Classify through (no floor) versus blind (flat or conical floor), and stacks of coaxial cylinders as counterbores or countersinks. Record diameter or diameters, depth, axis, entry face and entry point.
- Pockets: a planar floor whose normal opposes the opening direction, enclosed by walls (planar or cylindrical) that form closed loops, with convex-edge islands as inner loops. Record opening direction, depth, floor face, wall faces, outer contour, island contours and corner radii. Open slots and steps come after closed pockets.
- Orientation: the model is placed with its top at z0, so the first version only recognizes features opening along Z (3-axis work). Features along other axes are found and flagged as "needs another setup", not hidden.
- Selection: a feature is a group of faces. Clicking any face of a feature in a "feature" selection mode selects the whole feature; a panel list (Holes, Pockets) with their parameters selects from the list too, and highlights the feature's faces in a distinct color. The user can always fall back to plain face selection when recognition is wrong.
- Honesty about limits: heuristics have false positives and misses on fillets, drafted walls, threads, B-spline walls and merged features. Each feature gets a status and diagnostics. Validate against real CAD exports from more than one system, not only generated fixtures.
- Not in this step: toolpath generation or machining targets. The contours of a feature (entry loop, floor loop) are exposed as candidates for the explicit machining targets and validated contour conversion listed under later work.
- Tests: generated fixtures with expected counts and parameters: through hole, blind hole, counterbore, countersink, rectangular pocket with corner radii, pocket with an island, stepped pocket, open slot, a block with none; a feature along X flagged; the group selection round trip between canvas and list.

## Step 9 — Assemblies (later)

Resolve representation relationships, mapped items and occurrence transforms with units in the correct coordinate spaces. Use occurrence-path IDs for independently selectable repeated parts. Test nested/repeated/mixed-unit instances against a reference viewer.

## Hardening and later work

Starts with step 1. Swift tests and generated fixtures first; add the original box, real holes/fillets/B-splines, multi-body parts, assemblies and 50–100 MB files. Profile peak memory/responsiveness; mmap alone does not bound cache or geometry expansion. Add import progress/diagnostics UI in step 2.

Invariants: finite coordinates, optional valid bounds, endpoints match scaled source vertices, deterministic order/IDs for a given import, unique edges per body, and reachable/emitted/skipped counts (not every EDGE_CURVE in the file).

Later: explicit machining targets from selected faces and features, and validated contour conversion. Preserve source coordinates; automatic Y-up reorientation is deferred.
