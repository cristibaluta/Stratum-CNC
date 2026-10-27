# Toolpath panel: issues to tackle

Source: review of `cam/panels/PanelToolpathDetails.swift` and `cam/toolpaths/*`.

Note: which general fields each operation shows (End Z, Stepdown, Stepover, Entry) comes from `SC.OperationRequirements` in StratumCAM, which wasn't in the review. Those items are inferred from `OperationDefaults` and code comments, and marked **(verify)**.

**Rule agreed for stepover:** it is always stored and edited as a percentage of the tool diameter. The mm value is only a calculated read-out.

Each issue is numbered so we can work through them one by one. Tick the box when done.

---

## A. Stepover

### [ ] #1: Store stepover as % of diameter, not mm (priority: high)
- **Where:** `ToolpathData.stepOver`, `PanelToolpathDetails.stepOverPercent`, `OperationDefaults.applyDefaults`, `ToolpathGenerator.makeSettings`, `ToolpathGenerator.logJobSummary`.
- **Problem:** `stepOver` is stored in mm. The panel converts to and from % on every read and write (`stepOverPercent` binding, clamped 10–95). Side effects:
  - Changing the tool changes the effective percentage, because the mm value stays fixed.
  - `applyDefaults` converts fraction → mm, and `makeSettings` converts mm → fraction, so the same number is converted back and forth.
  - Logs print stepover in mm.
- **Fix:**
  - Store `stepOverPercent` (or a fraction) in `ToolpathData` and bind the field to it directly.
  - Keep the 10–95 % clamp at that single place.
  - Compute the mm figure only for the note under the field (`stepOverNote`).
  - `OperationDefaults.stepOverFraction` already fits this model.
  - `makeSettings` passes the value straight to `SC.CuttingData.stepoverPercentage`.
  - **Migration:** `init(from:)` must read the legacy mm `stepOver` key and convert it with the saved tool's diameter, so old projects keep working.
- **Check afterwards:** switching tool keeps the percentage, and the mm note updates.

### [ ] #2: Stepover sits after Entry in Pocket (priority: medium)
- **Where:** `PanelToolpathDetails.rowOperationOptions`.
- **Problem:** the order is Direction → Pattern → Entry → Ramp angle → Ramp feed → Stepover. Stepover is about clearing, so it belongs next to the pattern.
- **Fix:** render Stepover directly under the pattern (and its detail row), before Entry. Same for Counterbore.

### [ ] #3: Facing has no stepover control (priority: low)
- **Where:** `SC.MachiningOperations+FormFields.swift` (comment: the engine derives row spacing from the tool diameter).
- **Problem:** with a large facing cutter the user can't control overlap.
- **Fix:** ask the library to expose it, or show a read-only note with the value the engine uses.

---

## B. Missing features

### [ ] #4: Contour holding tabs (priority: high)
- **Where:** `OperationOptionsView.hiddenFieldIDs` (`contour.tabs`), `ToolpathData+Operation`, `ToolpathGenerator.makeOperation` (passes `tabs: []`).
- **Problem:** the engine and form support tabs, but `ToolpathData` doesn't store them. Without tabs, a cut-out part ends up loose.
- **Fix:** add a tabs array to `OperationSettings` (Codable, optional key), write it back in `apply`, pass it in `makeOperation`, unhide `contour.tabs`.

### [ ] #5: Contour lead-in / lead-out (priority: medium)
- **Where:** `hiddenFieldIDs` (`contour.leadIn`, `contour.leadOut`), `makeOperation` (passes `nil`).
- **Problem:** same as #4, not stored.
- **Fix:**
  - Store both and unhide them.
  - The library rejects lead-in combined with ramp/helix entry (`parameterMessage` already handles it).
  - The UI should prevent or explain that combination instead of failing at Preview.

### [ ] #6: No stock to leave / finishing pass (priority: medium)
- **Where:** nowhere in `ToolpathData` or `OperationSettings`.
- **Problem:** pockets and contours usually want a roughing pass with an allowance, then a finishing pass.
- **Fix:** needs engine support first. Then add an allowance field (and a finishing-pass toggle) to the general fields.

### [ ] #7: "Through stock" depth helper for hole operations (priority: low)
- **Where:** Depth section, for Drill / Bore / Thread mill (default End Z is fixed at -3).
- **Fix:** a button or toggle that sets End Z from the stock thickness in `PanelStockMaterial`.

---

## C. Field behaviour and validation

### [ ] #8: Pocket loop pitch and optimal load aren't clamped (priority: medium)
- **Where:** `OperationOptionsView.patternDetail`.
- **Problem:** these are plain `InspectorNumberField`s. The generic fields clamp to the library range, so these are inconsistent. Errors only appear at Preview (trochoidal 5–100 %, adaptive > 0 and ≤ 95 % of Ø).
- **Fix:** clamp to the engine's accepted ranges.

### [ ] #9: Adaptive "Optimal load" unit mismatch (priority: medium)
- **Where:** `patternDetail` (unit `mm`) vs `ToolpathGenerator.parameterMessage` ("at most 95 % of the tool diameter").
- **Problem:** the field is in mm, the error talks in %. A 3 mm tool with a 3 mm load fails.
- **Fix:** edit it as % of tool diameter, like stepover (#1), with an mm read-out. This also unifies the radial-engagement units (stepover % of Ø, loop pitch % of radius, optimal load mm).

### [ ] #10: Slot outline must equal tool width, shown only as an error (priority: low)
- **Where:** `ToolpathGenerator.run` (`rectangleSlotCenterline`, tolerance 0.05).
- **Fix:** when "Selection is" = Slot outline, show a note: "Outline must be Ø X mm wide".

### [ ] #11: Facing may be a single full-depth pass **(verify)** (priority: medium)
- **Where:** `OperationKind.defaults` (facing has End Z only, no Stepdown).
- **Problem:** if `usesStepdown` is false for facing, a deep facing cut is taken in one pass.
- **Fix:** check `requirements`. If confirmed, either expose Stepdown or warn above a depth threshold.

### [ ] #12: Facing can only target the selection's bounding box (priority: low)
- **Fix:** add a "Whole stock" option using the stock dimensions.

---

## D. Grouping and layout

### [ ] #13: Plunge feed is unreachable for Drill, Bore, Thread mill, Chamfer **(verify)** (priority: high)
- **Where:** `OperationOptionsView.rampingRow`. `plungeRate` is only edited here, and this row only shows when `requirements.usesEntry`.
- **Problem:** operations without an entry strategy can't edit the plunge feed. If the engine uses it for drilling, that's a real gap.
- **Fix:** see #14. With the plunge feed in the Tool section it is always available.

### [ ] #14: Feeds are split between sections, and "Ramp feed" is mislabelled (priority: medium)
- **Where:** `rowTool` (Spindle, Feed rate) vs `rampingRow` (Ramp feed).
- **Problem:** the plunge feed sits in Operation and is called "Ramp feed" even when Entry is Off.
- **Fix:** move it next to Feed rate in the Tool section as "Plunge feed". Consider renaming the section "Tool & feeds". Keep Entry and Ramp angle in Operation.

### [ ] #15: Stepdown-like values are scattered (priority: medium)
- **Where:**
  - Stepdown → Depth section.
  - Slot "Depth per pass" → Operation (`slotDepthPerPass`).
  - Drill "Peck depth" → Operation.
  - Counterbore "Depth" → Operation.
- **Fix:** one place in Depth, where the field's meaning depends on the operation (stepdown / depth per pass / peck depth). Could map `slotDepthPerPass` onto `toolpath.stepDown`. Note that `rampingButton` already special-cases the slot.

### [ ] #16: Counterbore depth: wrong section and wrong sign convention (priority: medium)
- **Where:** `OperationSettings.counterboreDepth` (positive) vs End Z (negative); `ToolpathGenerator.makeSettings` uses `abs(depth)`.
- **Problem:** the Depth section shows Start Z, Stepdown, Clearance Z but no depth.
- **Fix:** show it in the Depth section as End Z, using the same sign as other operations (or label it clearly).

### [ ] #17: "Clearance Z" is a height inside a section called "Depth" (priority: low)
- **Fix:** rename the section ("Z levels" or "Heights").

### [ ] #18: Optional fields show a generic "Value" row (priority: low)
- **Where:** `ParameterFieldsView`, `.optionalDouble` (title hardcoded "Value").
- **Problem:** Peck depth, Dwell time and Depth override all show a toggle followed by a row labelled "Value".
- **Fix:** use the field's own label for the number row.

### [ ] #19: Chamfer layout (priority: low)
- **Where:** `OperationOptionsView.body`, `hiddenFieldIDs` (`chamfer.params.side`).
- **Problems:**
  - The Side picker sits above the "Chamfer" subheader instead of inside it. The subheader is also redundant, since the operation is already Chamfer.
  - The resulting depth (derived from width and V-bit angle) is never shown.
- **Fix:** drop the subheader or put Side inside the group, and add a note: "Depth = X mm for a Y° bit".

### [ ] #20: Selection hint is hidden (priority: medium)
- **Where:** `OperationKind.selectionHint` is only used as a `.help` tooltip on the Type button. The Shapes section comes before the operation is chosen.
- **Fix:** show it as an `InspectorNote` in the Shapes section, next to "Selected: N shapes". Slot still needs its source-dependent text.

### [ ] #21: No tool compatibility feedback (priority: medium)
- **Where:** `ToolPicker`, `ToolpathGenerator.message`.
- **Problem:** Chamfer needs a V-bit, Thread mill needs a thread mill, and Counterbore needs a diameter larger than the tool. These only fail at Preview.
- **Fix:** a warning note in the Tool section when the tool doesn't fit the operation.

---

## E. Smaller UX and copy fixes

### [ ] #22: Thread mill: hint and summary vs the Internal toggle (priority: low)
- **Where:** `OperationKind.summary` / `selectionHint` say "existing hole", but `threadIsInternal` allows external threads.
- **Fix:** align the copy with what the toggle allows (or drop external threads).

### [ ] #23: Typo in thread mill hint (priority: low)
- "Select and existing hole" → "Select an existing hole".

### [ ] #24: Thread mill has no climb/conventional choice (priority: low)
- **Fix:** check whether the library offers it for thread milling.

### [ ] #25: Bore: "Shift before retract" needs a help text (priority: low)
- **Fix:** add a `.help` or note explaining what it does (e.g. moving the tool off the wall before retracting, to avoid marking the bore).

### [ ] #26: Engrave tool mapping TODO (priority: low)
- **Where:** `ToolpathGenerator.makeTool`: "engraving tool length can be nil" and `Tool.type` isn't mapped (everything is a flat end mill except chamfer).
- **Fix:** decide how to handle a nil length and map V-bits for engraving.

---

## F. Stale code and docs

### [ ] #27: `toolpaths/INFO.md` describes the old panel (priority: low)
- It lists rowFooter, Generate, "SPINDLE SPEED", "SAFE Z", etc., and not the current Shapes / Operation / Tool / Depth / Preview sections.
- **Fix:** regenerate it from the current view tree.

### [ ] #28: `GenerationError.noShapes` message refers to a removed button (priority: low)
- **Where:** `ToolpathGenerator.swift`: "use \"Select shapes\" and click them on the canvas".
- **Fix:** "Click shapes on the canvas to select them."

---

## Suggested order
1. #1, #2 (stepover model and placement; touches saved data, so do first)
2. #13, #14, #15, #16, #17 (regrouping of fields in the panel)
3. #4, #5 (contour tabs and lead-in/out)
4. #8, #9, #18, #20, #21 (validation and hints)
5. The rest as polish.
