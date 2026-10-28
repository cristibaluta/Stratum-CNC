# Rest machining: implementation plan

Goal: after a pocket is previewed, show the corners its tool couldn't reach, and let the user create a **rest operation** (smaller tool) from them. The rest operation is a normal entry in the toolpaths panel.

**Decision: linked.** A rest toolpath stores the ID of its source pocket and recomputes the corners from it on every Generate. It never keeps a copy of the corners.

Work in order. Each step should build and be checked before starting the next.

---

## Step 1: Harden `restCorners` (library)

File: `StratumCAM/toolpaths-engine/SCEngine+RestCorners.swift`

Verified correct: line-to-line convex corners, CW and CCW, reflex corners ignored. Fix the gaps found in review:

1. **Minimum depth filter.** Skip a corner when `centerDistance - toolRadius < minDepth`. Add a `minDepth` parameter, default about 0.03 mm. Without it, an SVG circle imported as 64 lines reports 64 corners about 0.002 mm deep.
2. **Don't drop corners silently.** When a wall is shorter than the tangent distance, keep the corner and clamp the tangent points to the wall ends (or report it as skipped). Decide which and document it.
3. **Tool fit check.** Skip a corner if the tool centre `o` would fall outside the pocket (pocket narrower than the tool).
4. **Stock to leave.** Callers that leave an allowance on the walls should pass `toolRadius + allowance`, so the regions match what is really left. Check the two call sites (`SCEngine+Pocketing.swift` line ~318 and `SCEngine+Allowance.swift` line ~80).
5. **Out of scope for now (write down as known limits):** line-to-arc corners, concave arcs tighter than the tool, islands.

Done when: unit tests cover a square, a rectangle, an L-shape, a 64-gon circle (no corners), and a short-wall triangle.

---

## Step 2: Rest toolpath generation (library)

New file: `SCEngine+RestMachining.swift`

Signature (adjust to taste):

```swift
func generateRestToolpaths(corners: [SC.RestCorner],
                           tool: SC.ToolParams,       // the smaller tool
                           settings: SC.MachineSettings) throws -> [SC.OutputToolpath]
```

Per corner:
1. Build a small **corner polygon**: the corner point, extended along both walls past the big tool's tangent points by a margin of at least the small tool's radius, then closed through area the big tool already cleared.
2. Run it through the existing pocket engine (offset pattern) with the small tool, same Z layers as the settings.
3. Return one `OutputToolpath` per corner, or merge them into one with rapids between corners.

Rules:
- Throw `toolIncompatible` if `tool.diameter >= corner.toolRadius * 2`.
- Skip a corner when the small tool can't improve it (leftover smaller than the small tool's own corner rounding), and report how many were skipped.
- Do not use `region` directly as the pocket boundary: its tip has zero width and the offset collapses (`geometryCollapsed`).

Done when: a 20x20 square pocket cut with a 6 mm tool, then a 2 mm rest pass, gives valid passes for all four corners that stay within the corner polygons.

---

## Step 3: Model and validation (app)

Files: `toolpaths/operations/OperationKind.swift`, `OperationSettings.swift`, `OperationDefaults.swift`, `ToolpathData.swift`, `ToolpathData+Operation.swift`

1. Add `OperationKind.restMachining`: title, symbol, `nextName` ("Rest 1"), defaults.
2. Add `OperationSettings.restSourceID: UUID?`.
3. Keep decoding of old projects working (new optional keys use `decodeIfPresent`).
4. Define what the rest operation uses: tool, feeds, Z levels, stepover. It does **not** use selected shapes, so `hasGeometry` must be true when `restSourceID` is set.
5. Validation: source must exist and be a pocket, and the rest tool must be smaller than the source tool.

Done when: a rest toolpath can be created in code, saved, and reloaded.

---

## Step 4: Generation of a linked rest toolpath (app)

Files: `ToolpathGenerator.swift`, `CAMModel.swift`, `ToolpathGeneration.swift`

1. `ToolpathGenerator.prepare`: for a rest toolpath, resolve the source `ToolpathData` and build the source `Job` too.
2. Get the source corners: reuse `generations[sourceID]` when `isCurrent(for:)` is true, otherwise run the source job first. Do both in the same background task.
3. Pass corners and the rest tool to the Step 2 function.
4. Outdated detection: `isCurrent` compares only the toolpath's own data today. For a rest toolpath it must also compare the source toolpath's data, so editing the pocket marks the rest preview outdated.
5. Errors to show: source deleted, source not a pocket, source has no corners ("Nothing left to machine in the corners").
6. `deleteToolpath` on a source: decide whether rest toolpaths linked to it are deleted, or kept and shown with a "source missing" state. Recommended: keep and flag.

Done when: editing the pocket's tool or shape and pressing Generate on the rest toolpath gives updated corners.

---

## Step 5: Preview overlay for rest regions (app)

Files: `ToolpathGeneration.swift`, `CAMModel.swift`, `D2_CanvasState.swift`, `D2_RenderObjectBuilder.swift`, `ToolpathPathBuilder.swift`

1. `ToolpathPathBuilder.restPath(for:)`: turn each `corner.region` (two lines and an arc) into a `CGPath`, chord-approximating the arc like the existing code.
2. Build it in the background step of `generateToolpaths` next to `previewPath`; store as `restPath` on `ToolpathGeneration`.
3. `D2_CanvasState.restRegionsPath` with a setter, like `setToolpathsPath`.
4. `D2_RenderObjectBuilder.restRegionsRenderObject` in a distinct colour (outline first; filled needs a triangle primitive, later).
5. Show regions only for the open toolpath, and only when "Show rest areas" is on. Hide them while scrubbing.

Done when: previewing a pocket with a large tool shows the corner regions on top of the shapes.

---

## Step 6: UI (app)

Files: `panels/PanelToolpathDetails.swift`, `toolpaths/operations/OperationOptionsView.swift`, `CAMView.swift`, `panels/PanelToolpaths.swift`

1. In the Preview section: toggle "Show rest areas", and a button **"Create rest operation"** shown only when the current generation has rest corners.
2. The button calls `CAMModel.addRestToolpath(from: id)`: copies settings and Z levels from the source, sets `restSourceID`, picks a default smaller tool, adds it to `toolpaths`, opens it.
3. Panel for a rest toolpath: hide "Shapes", show "Source: <pocket name>", keep Tool & feeds and Z levels. Warn when the tool is not smaller than the source tool.
4. Toolpaths list row: show the rest operation with its icon and the source name as subtitle.
5. Update `toolpaths/INFO.md` with the new sections.

Done when: the full flow works: preview pocket, see regions, click create, new toolpath appears in the list, Generate shows the small-tool paths.

---

## Step 7: G-code and checks

Files: `ToolpathGCodeBuilder.swift`, `MakeraGCodeHeaderWriter.swift`

1. Confirm the G-code builder handles the rest toolpath's `OutputToolpath` without changes; check tool-change handling when the rest tool differs from the pocket tool.
2. Make sure toolpath order in the list is the machining order (rest after its source).
3. Manual test list:
   - square pocket, 6 mm then 2 mm
   - SVG circle pocket (no rest corners expected)
   - delete the source
   - change the source tool after creating the rest toolpath, then regenerate
   - save and reload the project

---

## Known limits (write into the UI notes later)

- Only line-to-line corners are detected.
- Pockets with islands: only the outer boundary is checked.
- The regions are geometric (final wall minus the tool circle). They don't model the roughing paths actually cut.