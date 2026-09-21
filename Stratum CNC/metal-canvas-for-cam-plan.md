# Reusing `MetalCanvasView` in CAM (instead of `CAM_2D_View`)

Goal: draw CAM's vectors and toolpaths with Metal, while keeping shape
selection via mouse, and letting the Metal view take a caller-supplied list
of default objects (CAM wants ruler + stock, not anchor + bed).

## The key finding that makes this feasible

`Camera` in `metal-canvas` is **already orthographic** (`Camera.updateMatrix()`
builds an ortho projection; `fov`/`distance` only set the ortho half-extents).
And `StandardView.top` (`eye = (0,0,1)`, `up = (0,1,0)`) is *exactly* CAM's 2D
convention: X right, Y up, origin at world (0,0). So this isn't "add a 2D mode
to a 3D camera" — it's "lock the existing camera to the view it already
supports, and strip the 3D-only interactions."

The second key finding: `D2_CanvasState` / `D2_Object` / `PathSelection` (the
selection & data model used by the inspector, material panel, and toolpath
"select shapes" picking) have **no CoreAnimation dependency in their logic**
— only `D2_CanvasNSView` and `D2_ObjectNode` touch `CALayer`. So the plan
below leaves the data/selection model untouched and only swaps the
render+input backend underneath it.

## Gap analysis → workstreams

### A. Make the static/default-object set configurable

`RenderObject.fixtures(for:)` currently always bundles workbed+anchor+ruler.
Split it so a caller can ask for a subset:

- Controller keeps: `axes() + stockBox(for:) + fixtures(for:)` (workbed +
  anchor + ruler)
- CAM asks for: `stockBox(for:) + ruler(z:)` only — skip `.workbed`/`.anchor`

`CanvasSceneModel` is controller-specific (heightmap, tool, scrub state) —
don't force CAM through it. Give CAM a smaller `ObservableObject` that just
owns `renderObjects: [RenderObject]`, with the *caller* deciding which
default objects go in, not a hardcoded `defaultScene()`.

Also add a locked-camera mode to `MetalCanvasView`: call `camera.snap(to:
.top)` once, never call `camera.orbit(...)`, disable the orientation cube and
"snap to face" swipe (only one face exists). `CanvasInputSettings` is a
controller-only user preference panel — CAM should bypass it with a fixed
scroll→pan / pinch→zoom mapping rather than inherit orbit-capable defaults.

### B. Geometry adapter: `D2_Object` → `RenderObject`

New pure function, one `RenderObject` **per path** (not per object), so each
path keeps its own selection-driven color:

- Flatten `STBezierPath.cgPath` to a polyline (port `BezierPathFlattener`'s
  adaptive-cubic algorithm, currently `NSBezierPath`-based, to `CGPath` or
  convert once at import)
- Map each flattened point through `object.worldPoint(fromLocal:)` → world-
  space `SIMD3<Float>` at z=0
- Color: same rule as `D2_ObjectNode.updateStyles` (picked=orange,
  selected=red, path-selected=blue, default=label color)

`D2_CanvasState.toolpathsPath` (from `ToolpathPathBuilder`) gets the same
flatten-to-world treatment as one more `RenderObject`. Stock and ruler reuse
`RenderObject.stockBox(for:)` / `RenderObject.ruler(z:)` directly — no new
geometry code needed there.

### C. Watch out: color is baked into the vertex buffer

`MetalRenderer.updateGeometry` caches GPU buffers keyed by `RenderObject.id`
and reuses the buffer untouched if the id is unchanged — including when only
`.color` differs. That's fine for the controller (ids get replaced on
structural changes, not per-frame), but CAM recolors on every click.

Plan: mint a **fresh id** whenever a path's rendered state changes and let it
rebuild — cheap here, since individual vector shapes are tiny next to G-code
toolpaths (the case that caching was built for). Flag as a decision point if
a project ever has thousands of paths (e.g. dense Gerber pours) — fallback
would be a per-batch color uniform instead of baked-in vertex color.

### D. Hit testing in world space

Add `Camera.worldPoint(atScreenNDC:)`, generalizing the math already inline
in `Camera.zoom(to:towards:)`. Rewrite `PathHitTester.hitTest` to work
directly against world-space `CGPath`s (built in the same pass as B) instead
of per-node local CALayer coordinates — same
`strokingWithWidth(...).contains(point)` test, just a different coordinate
space to get the click into. Cache the world-space `CGPath` per path
alongside its `RenderObject` so a mouse-down doesn't re-flatten.

### E. Mouse interaction

`MetalCanvasView`'s `InteractiveMTKView` already overrides `scrollWheel`; add
`mouseDown`/`mouseDragged`/`mouseUp` overrides the same way, forwarding to
the coordinator. Port `D2_CanvasNSView.mouseDown/mouseDragged/mouseUp` (the
`pendingPick`/`dragMode`/`clickDragThreshold` state machine) almost
verbatim — the only substitution is `layer?.convert(...)` →
`camera.worldPoint(atScreenNDC:)`. Every call into `D2_CanvasState`
(`selectPath`, `togglePathSelection`, `moveObject`, `togglePickedPath`) stays
identical. Pan/zoom already have Metal-side equivalents (`Camera.pan`,
`Camera.zoom(to:towards:)`) — reuse as-is.

### F. Visual parity items

Do a QA pass, not blockers:

- Dashed selection box (`RenderObject.isDashed` already exists, built for
  the 3D occlusion case — reuse directly)
- Stock hatch texture (port as extra hairline geometry, or ship flat fill
  first and add the hatch as a fast-follow)
- True-to-life 1mm:1pt zoom (`D2_CanvasNSView.trueToLifeZoomScale`) needs a
  `Camera.distance`-based equivalent computed once on load

## Suggested sequencing

So nothing breaks mid-flight:

done 1. Land the configurable-fixtures + locked-camera-mode refactor (A) — zero
   behavior change for the controller, verify against existing usage.
done 2. Build the D2→RenderObject adapter (B+C) as a standalone, testable
   function — no view changes yet.
done 3. Stand up a new Metal-based CAM view **behind a flag**, `CAM_2D_View`
   keeps shipping in parallel. Landed as `CAM_Metal_View` + `CAMSceneModel`
   (`cam/renderer-metal/`), switched by `CAMFeatureFlags.metalCanvasKey`.
   Draw-only: no mouse selection yet (step 4).
done 4. Port hit testing + mouse interaction (D+E); verify selection, shift/cmd
   multi-select, "select shapes" picking mode, drag-to-move, and the
   rotation-center handle match today's behavior.
   Landed as `PathHitTester+World`, `CAMCanvasInteraction`, `CAMSelectionOverlay`,
   `Camera.worldPoint(atScreenNDC:)` and `CanvasPointerHandler` (the seam
   `MetalCanvasView` reports the mouse through). Not yet checked by hand —
   walk the list above with the flag on.
done 5. Visual QA pass (F).
done 6. Swap `CAMView.body`'s `CAM_2D_View(...)` for the new view; delete
   `D2_CanvasNSView` / `D2_CanvasRenderer` / `D2_ObjectNode` / `StockLayer` /
   `RulerShapeLayer` / `CenterShapeLayer`. `D2_CanvasState`, `D2_Object`,
   `PathSelection`, and a rewritten `PathHitTester` survive.
   Removed the now-pointless `CAMFeatureFlags.metalCanvasKey` toggle and its
   DEBUG overlay too, since there's only one canvas left to switch between.
   The layer-based `PathHitTester.hitTest` overload (the one that took
   `[UUID: D2_ObjectNode]`) is gone; `PathHitTester+World`'s
   world-space overload is the only one left.

## Decisions to make before starting

- Ship the stock hatch texture in v1, or flat fill first?
- Is the rotation-center drag handle (orange dot) required for v1?
- Worth checking real project `D2_Object.paths.count` (dense Gerber files
  especially) before committing to "rebuild the `RenderObject` on every
  selection change" as the default strategy — if that number is large, the
  per-batch color-uniform fallback in (C) becomes worth doing up front
  instead of after the fact.
