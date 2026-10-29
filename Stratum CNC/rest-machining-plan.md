# Rest machining: implementation plan (rev. 2)

Goal: after a pocket is previewed, show the corners its tool couldn't reach, and let the user create a **rest operation** (smaller tool) from them. The rest operation is a normal entry in the toolpaths panel.

**Decision: linked.** A rest toolpath stores the ID of its source pocket in `OperationSettings.restSourceID: UUID?` and recomputes the corners from it on every Generate. It never keeps a copy of the corners.

Work in order. Each step should build and be checked before starting the next.

Status: Steps 1–6 done, 7 partly. Nothing has been run in the app yet. The library lives in `../StratumCAM` (outside this workspace, edited there).

## What changed since rev. 1

- `ToolpathGenerator.prepare(for:canvasState:)` returns a `Job` (contours, tool, settings, operation, startZ, derivesSlotCenterline). `ToolpathGenerator.run(_:)` is static and thread-safe. Generation is in `CAMModel.generateToolpaths(for:)`, which builds a `ComputedGeneration` (outcome, `previewPath`, `scrub`) in a detached task and applies it in `finishGeneration`.
- `OperationKind` is switched over exhaustively in several places (`title`, `symbol`, `summary`, `selectionHint`, `groups`, `ToolpathGenerator.makeOperation`). A new case must be handled in all of them.
- `ToolpathGeneration.isCurrent(for:)` is only `source == toolpath`.
- There is now a scrub preview (`scrubbableGeneration`, `syncScrub`) and hidden toolpaths (`hiddenToolpathIDs`). The overlay must respect both.
- `PanelToolpathDetails` is a plain struct with closure callbacks (`onGenerate`, `onAddNext`, ...), and shape picking is driven by `CAMModel.syncPickingWithSelection`.

---

## Step 1: Harden `restCorners` (library) ✅ DONE

File: `StratumCAM/toolpaths-engine/SCEngine+RestCorners.swift`

Verified correct earlier: line-to-line convex corners, CW and CCW, reflex corners ignored. Fix the gaps:

1. **Minimum depth filter.** Skip a corner when `centerDistance - toolRadius < minDepth`. Add a `minDepth` parameter, default about 0.03 mm. Without it, an SVG circle imported as 64 lines reports 64 corners about 0.002 mm deep.
2. **Don't drop corners silently.** When a wall is shorter than the tangent distance, keep the corner and clamp the tangent points to the wall ends (or report it as skipped). Decide which and document it.
3. **Tool fit check.** Skip a corner if the tool centre `o` would fall outside the pocket.
4. **Stock to leave.** Callers pass `toolRadius + allowance`, so the regions match what is really left. `ToolpathGenerator.makeSettings` already passes `stockToLeave` as `allowance`; the app must use the same value when asking for corners. Check the two library call sites (`SCEngine+Pocketing.swift` ~318, `SCEngine+Allowance.swift` ~80).
5. **Known limits:** line-to-arc corners, concave arcs tighter than the tool, islands.

Done when: unit tests cover a square, a rectangle, an L-shape, a 64-gon circle (no corners), and a short-wall triangle.

---

## Step 2: Rest toolpath generation (library) ✅ DONE

New file: `SCEngine+RestMachining.swift`

```swift
func generateRestToolpaths(corners: [SC.RestCorner],
                           tool: SC.ToolParams,       // the smaller tool
                           settings: SC.MachineSettings) throws -> [SC.OutputToolpath]
```

Per corner:
1. Build a small **corner polygon**: the corner point, extended along both walls past the big tool's tangent points by at least the small tool's radius, then closed through area the big tool already cleared.
2. Run it through the existing pocket engine (offset pattern) with the small tool, same Z layers as the settings.
3. Return one `OutputToolpath` per corner, or merge them with rapids between corners.

Rules:
- Throw `toolIncompatible` if `tool.diameter >= corner.toolRadius * 2`.
- Skip a corner the small tool can't improve, and report how many were skipped.
- Don't use `region` directly as the pocket boundary (zero-width tip collapses: `geometryCollapsed`).

**Decision:** the app calls this function directly. Do not add a `.restMachining` case to `SC.MachiningOperation`: a rest operation has no contours of its own, so it doesn't fit that model.

Done when: a 20x20 square pocket cut with a 6 mm tool, then a 2 mm rest pass, gives valid passes for all four corners within the corner polygons.

---

## Step 3: Model and validation (app) ✅ DONE

Files: `operations/OperationKind.swift`, `OperationSettings.swift`, `ToolpathData.swift`, `ToolpathData+Operation.swift`, `ToolpathGenerator.swift`, `ToolpathDetailsModel.swift`

1. Add `OperationKind.restMachining`: title "Rest", symbol, summary, `selectionHint` (nil), added to `groups` after `.pocket`. `nextName` gives "Rest 1" from the title.
2. Add `OperationSettings.restSourceID: UUID?` (`decodeIfPresent`, so old projects load). Cover it in `ProjectPersistenceTests`.
3. `ToolpathGenerator.makeOperation(from:)` and `ToolpathData.machiningOperation` have no library equivalent for rest. Give rest an explicit branch (reuse `.pocket` with the rest tool for requirements, i.e. End Z and stepdown yes, tabs and lead-in no) so the form and `validateOptions` keep working. Make sure no exhaustive switch is left unhandled.
4. `hasGeometry` is true for a rest toolpath when `restSourceID != nil`. Selected shapes are not used. `toolCompatibilityWarning` gets a rest case.
5. Validation that needs other toolpaths (source exists, is a pocket, rest tool smaller than source tool) can't live in `validateOptions(of:)`. Do it in `ToolpathGenerator.prepare`, which receives the source.

Done when: a rest toolpath can be created in code, saved, and reloaded.

---

## Step 4: Generation of a linked rest toolpath (app) ✅ DONE

Files: `ToolpathGenerator.swift`, `CAMModel.swift`, `ToolpathGeneration.swift`

1. Make the job a rest variant, e.g. `Job.rest(source: Job, restTool:, settings:, ...)`. `prepare` takes the source `ToolpathData` too (`prepare(for:source:canvasState:)`), and the rest branch runs **before** the `hasGeometry` / `.noShapes` guard.
2. `run` for a rest job, in one detached task: run the source job, compute `restCorners` (with `toolRadius + allowance`), call `generateRestToolpaths`, then `droppingPasses(above:)`.
3. Always compute corners for a pocket source and store them (`restCorners: [SC.RestCorner]`) in `ComputedGeneration` / `ToolpathGeneration`. The overlay (Step 5) and the "Create rest operation" button use them. The rest job recomputes from its own run of the source, so it doesn't depend on another generation being current.
4. **Outdated detection.** `ToolpathGeneration` stores `sourceSnapshot: ToolpathData?` (the pocket's data at generation time). `isCurrent(for:)` becomes `isCurrent(for toolpath:, linkedSource: ToolpathData?)`: own data equal and, for rest, snapshot equal to the current source. Update all callers: `PanelToolpathDetails` (several), `scrubbableGeneration`, `ToolpathGCodeBuilder` if it checks currency.
5. New `GenerationError` cases and messages: `sourceMissing`, `sourceNotPocket`, `noRestCorners` ("Nothing left to machine in the corners"), `restToolNotSmaller`.
6. Deleting a source: keep the rest toolpath and show "source missing" (error from item 5). Don't cascade.
7. Picking: `syncPickingWithSelection` must not start picking for a rest toolpath.

Done when: editing the pocket's tool or shape and pressing Preview on the rest toolpath gives updated corners, and the rest preview shows "Outdated" after the pocket is edited.

---

## Step 5: Preview overlay for rest regions (app) ✅ DONE

Files: `ToolpathGeneration.swift`, `CAMModel.swift`, `D2_CanvasState.swift`, `D2_RenderObjectBuilder.swift`, `ToolpathPathBuilder.swift`

Follow the existing `previewPath` pattern.

1. `ToolpathPathBuilder.restPath(for:)`: each `corner.region` (two lines and an arc) as a `CGPath`, chord-approximating the arc like the existing code.
2. Build it in the detached task in `generateToolpaths` next to `previewPath`; store as `restPath` in `ComputedGeneration` and `ToolpathGeneration`.
3. `D2_CanvasState.restRegionsPath` with a `setRestRegionsPath`, like `setToolpathsPath`.
4. `D2_RenderObjectBuilder.restRegionsRenderObject` in a distinct colour (outline first; fill later).
5. Show only for the open pocket whose generation is current, and only when "Show rest areas" is on (state in `CAMModel`, like `hiddenToolpathIDs`). Hide while `toolpathScrub != nil`. Clear it when the selection changes or generations are discarded (`discardGenerations`).

Done when: previewing a pocket with a large tool shows the corner regions on top of the shapes.

---

## Step 6: UI (app) ✅ DONE

Files: `panels/PanelToolpathDetails.swift`, `ToolpathDetailsModel.swift`, `OperationOptionsView.swift`, `CAMView.swift`, `panels/PanelToolpaths.swift`

1. `PanelToolpathDetails` new inputs: `restCornerCount: Int = 0`, `restSourceName: String? = nil`, `showRestAreas` (binding or value + callback), `onCreateRest: () -> Void = {}`.
2. In `rowPreview`: "Show rest areas" toggle and a **"Create rest operation"** button, shown only for a pocket whose generation is current and has `restCornerCount > 0`.
3. `CAMModel.addRestToolpath(from:)`: copies settings and Z levels from the source, sets `restSourceID`, picks a default smaller tool, inserts it right after the source in `toolpaths` (so list order is machining order), and opens it.
4. For a rest toolpath: `rowShapes` shows "Source: <pocket name>" (or "Source missing" in orange) instead of the click-to-select label; hide the facing/slot/tab parts. Update `ToolpathDetailsModel.shapesTitle` and `previewButtonHelp`. Warn when the tool is not smaller than the source tool.
5. Toolpaths list row: rest icon, source name as subtitle.
6. Update `cam/toolpaths/INFO.md`.

Done when: the full flow works: preview pocket, see regions, click create, new toolpath appears after the pocket, Preview shows the small-tool paths.

---

## Step 7: G-code and checks 🟡 PARTLY

Files: `ToolpathGCodeBuilder.swift`, `MakeraGCodeHeaderWriter.swift`

1. `ToolpathGCodeBuilder` uses `ToolpathGenerator.makeSettings(from: generation.source)`; this works for rest because the rest toolpath's own data is the source. Confirm, check tool-change handling when the rest tool differs from the pocket tool, and that the header lists both tools.
2. Rest must come after its source in the list; reordering (`ToolpathDropDelegate`) should warn or keep that order.
3. Manual test list:
   - square pocket, 6 mm then 2 mm
   - SVG circle pocket (no rest corners expected)
   - pocket with stock to leave
   - delete the source
   - change the source tool after creating the rest toolpath, then regenerate
   - edit the source and check the rest preview shows "Outdated"
   - save and reload the project

---

## Known limits (write into the UI notes later)

- Only line-to-line corners are detected.
- Pockets with islands: only the outer boundary is checked.
- The regions are geometric (final wall minus the tool circle). They don't model the roughing paths actually cut.


Done: `minDepth` (default 0.03), clamped short walls (closed by a chord), tool-centre-inside check, `RestCorner.incomingWallLength/outgoingWallLength`, tests in `RestCorners_Tests.swift`. Pocket output already carries `restCorners` (`SCEngine+Pocketing.swift`, `SCEngine+Allowance.swift`), so the app doesn't call `restCorners` itself: it reads `outputs.flatMap(\.restCorners)`.
Note: `StratumCAM/Tests/.../Facing_Tests.swift` doesn't compile (pre-existing: calls private `facingScanlines`), which blocks `swift test` for the package; it was set aside temporarily to run the new tests.

Done: public `SCEngine.generateRestToolpaths(corners:tool:settings:direction:entry:)` in `SCEngine+RestMachining.swift`; new `SC.Warning.restCornersSkipped(count:)` (handled in `ToolpathGenerator.message(for: SC.Warning)`); tests in `RestMachining_Tests.swift`. Returns `[]` when nothing was cut. Ignores `allowance`/`finishingPass`.

Done: `OperationKind.restMachining` (title "Rest", symbol `angle`, summary, defaults; deliberately **not** in `OperationKind.groups`: it's created from a pocket, not picked), `OperationSettings.restSourceID` (`decodeIfPresent`), `makeOperation` describes it as an offset pocket, `hasGeometry` is `restSourceID != nil`, pattern picker and stock-to-leave rows hidden for it. App builds. Model tests are in `RestMachiningModelTests.swift`, but the test target doesn't compile for an unrelated, pre-existing reason (`ProjectPathsRegressionTests` uses `ProjectPaths.projectsRoot`), so they haven't been run. Validation that needs the other toolpaths (source exists, is a pocket, tool smaller) moves to Step 4.

Done (builds): `Job.restSource` + `prepareRest` (validates source exists, is a pocket, tool smaller) + `runRest` (runs the pocket, reads `outputs.flatMap(\.restCorners)`, calls `generateRestToolpaths`) in `ToolpathGenerator`; new `GenerationError` cases; `ToolpathGeneration.sourceSnapshot` / `isLinkedSourceOutdated` / `restCorners`; `CAMModel.refreshLinkedGenerations()` marks a rest result outdated when its pocket is edited (name ignored) or deleted, so `isCurrent(for:)` keeps its signature; `beginPicking` skips rest toolpaths. Deleting the source keeps the rest toolpath, which then fails with "no longer in the list". Not exercised in the running app yet.
Caution: edits to app files were made on disk; if Xcode shows an old version of a file, reload it from disk before saving.

Done (builds): `ToolpathPathBuilder.restPath(for:)`, `ToolpathGeneration.restPath` (built in the background task), `D2_CanvasState.restRegionsPath`, `D2_RenderObjectBuilder.restRegionsRenderObject` (pink outline, drawn after the toolpath in `CAMSceneModel.rebuild`), `CAMModel.showsRestAreas` + `updateRestRegions()` (only for the open pocket, while its result is current and nothing is scrubbed). Outline only; no fill.

Done (builds): panel shows "Show rest areas" and **Create rest operation** under Preview for a pocket with corners; `CAMModel.addRestToolpath(from:)` inserts the rest toolpath right after the pocket with a new tool (half the Ø, own id, so the G-code header numbers it as another tool) and opens it; a rest toolpath's panel shows "Source: <pocket>" (orange when missing) and warns when its tool isn't smaller; the list row shows the source name. Not done: `INFO.md` update.

Checked by reading: `ToolpathGCodeBuilder.plan` accepts a rest toolpath (it has geometry via its link) and `MakeraGCodeHeaderWriter` numbers tools by id, so the rest tool becomes its own T. Not done: warning when a rest toolpath is dragged above its pocket, and the manual test list below (needs the running app).