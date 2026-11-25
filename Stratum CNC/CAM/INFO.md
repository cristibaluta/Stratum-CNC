# Toolpath panel: view tree and data flow

Source of truth: `panels/PanelToolpathDetails.swift`, `toolpaths/operations/OperationOptionsView.swift`,
`toolpaths/ParameterFieldsView.swift`. Update this file when the sections change.

```
PanelToolpathDetails
└─ GroupBox
   └─ VStack
      │
      ├─ rowHeader                         [HStack]
      │  ├─ Image(operation symbol)
      │  └─ TextField(toolpath.name)       → sets isNameCustom = true on edit
      ├─ rowOperation: OperationPicker(operationKindBinding)   → renames via nextName() if !isNameCustom
      ├─ InspectorNote(operation summary)
      ├─ the operation's own fields         [OperationOptionsView, part .operation]
      │     contour / chamfer: Side (ContourPicker)
      │     pocket: Clearing pattern (PatternPicker + patternDetail)
      │     thread: standard, handedness, Internal, target diameter, pitch, radial passes
      │     bore / counterbore: target diameter / diameter · chamfer: width
      │     (everything the library defines except direction, depths and what the app draws itself)
      │
      ├─ InspectorSection "Shapes"
      │  ├─ "Area" Selection / Whole stock    ← facing only
      │  ├─ "Selection is" + width note       ← slot only (OperationOptionsView, part .shapes)
      │  ├─ "Selected": shapesLabel           ("N shapes selected", "Whole stock", orange "Click shapes to select")
      │  │                                      with shapes selected the row has a chevron and expands into shapeListRows:
      │  │                                      one line per shape / STEP edge (kind, Ø / R / length, distance to Z0), from CAMModel.shapeDetails
      │
      ├─ InspectorSection "Tool"
      │  ├─ ToolPicker(toolpath.tool)
      │  ├─ InspectorNote(toolCompatibilityWarning)   ← tool can't do the operation
      │  ├─ InspectorNote(presetNote)
      │  ├─ preset mismatch note + "Use recommended values"   ← ToolpathData.presetMismatch(for:), compared live, never saved
      │  └─ Spindle
      │
      ├─ InspectorSection "XY plane"          [OperationOptionsView, part .xyMovement]
      │  ├─ cut direction (climb / conventional)
      │  ├─ Feed rate
      │  ├─ stepOverRow (% of Ø + mm note)     ← if requirements.usesStepover, or facing
      │  ├─ facingExtensionRows                ← facing: Extension + FacingSidesButton → FacingSidesEditor popover
      │  │                                       (selection top view, a handle per side, dotted faced area; saved as operation.facingSides)
      │  └─ stockToLeaveRows                   ← if requirements.usesAllowance (pocket; contour on a side)
      │
      ├─ InspectorSection "Z axis"
      │  ├─ Start Z
      │  ├─ End Z                              ← counterbore: its own depth, shown as End Z
      │  │   └─ "Through stock" button         ← drill, bore, thread mill (exactly to the underside); contour (underside + 0.2 mm overcut)
      │  ├─ Depth per pass (slot) | Stepdown   ← each with a passes caption: "5 passes to Z −3 (last one 0.4 mm)"
      │  ├─ Peck drilling + Peck depth         ← drill only
      │  ├─ the operation's own depth fields   ← bore dwell / shift before retract, chamfer depth override (+ depth note)
      │  ├─ HoldingTabsButton                  ← contour
      │  └─ Clearance Z
      │
      ├─ InspectorSection "Entry"
      │  ├─ rampingRow (Entry, Entry angle)    ← if requirements.usesEntry
      │  ├─ Entry feed                         ← always, also for drill / bore / thread mill
      │  └─ LeadInOutRow ×2 (Lead-In, Lead-Out) ← contour: switch + summary + gear → LeadInOutEditor popover
      │
      ├─ InspectorSection "Preview"
      │  ├─ rowPreview: generationStatus + "Preview" button   (disabled without shapes, and on a lead-in/entry conflict). Opening the panel generates the toolpath by itself
      │  │                                      when it has shapes and no current result; the button refreshes it after an edit
      │  └─ rowScrub: slider through the generated moves
      │
      └─ rowBottomBar: Delete · Next toolpath · Done (Esc)
```

## Data flow

```
CAMView.toolpathSettingsPanel(for:)
   │  toolpath:       Binding<ToolpathData>   (via binding(for:))
   │  stockMaterial / stockThickness          (the setup's stock: camModel.stock(for:))
   │  siblingNames:   Set<String>             (other toolpaths' names, for nextName)
   │  isPicking:      camModel.pickingToolpathID == toolpath.id
   │  generation / isGenerating               (looked up from camModel by id)
   │  onGenerate → camModel.generateToolpaths(for:)
   │  onScrub    → camModel.setToolpathScrubStep(_:)
   │  onDone     → camModel.selectedToolpathID = nil
   │  onDelete   → camModel.deleteToolpath(_:)
   │  onAddNext  → adds the next toolpath and opens it
   ▼
PanelToolpathDetails
   ├─ operationKindBinding: writes operation.kind, applyDefaults(for:), and the name
   ├─ OperationOptionsView
   │    reads  toolpath.machiningOperation  (= ToolpathGenerator.makeOperation)
   │    writes toolpath.machiningOperation  (= ToolpathData.apply, in ToolpathData+Operation)
   │    stepover:   toolpath.stepOverPercent (% of Ø, clamped 10–95); mm is a read-out only
   │    pattern:    operation.pocketTrochoidalPitch (% radius), pocketAdaptiveLoadPercent (% Ø)
   │    tabs / lead-in/out: operation.contourTabs / contourLeadIn / contourLeadOut
   │    entry:      toolpath.ramping (shared by every operation with an entry)
   └─ rowTool / rowDepth / rowEntry write the general fields directly
        (End Z, Stepdown and Stepover follow the operation's defaults on a change of operation
         only while they still hold the old operation's default: see OperationDefaults)
```

## Where each value lives

| Value | Stored in | Notes |
|---|---|---|
| Stepover | `ToolpathData.stepOverPercent` | % of tool Ø; old projects stored mm and are converted on decode |
| Plunge feed | `ToolpathData.plungeRate` | also the ramp/helix feed |
| Stepdown | `ToolpathData.stepDown` | not used by slot |
| Slot depth per pass | `OperationSettings.slotDepthPerPass` | edited in Z axis |
| Peck depth | `OperationSettings.drillPeckDepth` (+ `drillUsesPecking`) | edited in Z axis |
| Counterbore depth | `OperationSettings.counterboreDepth` (positive) | shown as End Z, with the "−" in front |
| End Z | `ToolpathData.endZ` (negative) | typed as a positive depth |

## Rest machining

A rest toolpath (a `.pocket` with `OperationSettings.restSourceID` set, see `OperationSettings.isRest`) cleans the corners a pocket's larger tool couldn't reach, with a smaller tool.

- **Link:** `OperationSettings.restSourceID` is the pocket's `ToolpathData.id`. Corners are never stored: every Preview runs the pocket again (`ToolpathGenerator.runRest`), reads `restCorners` from its output and cuts them with `SCEngine.generateRestToolpaths`.
- **Created** from a previewed pocket ("Create rest operation", `CAMModel.addRestToolpath(from:)`), inserted right after it. It isn't in `SC.MachiningOperation.Kind.groups`.
- **Outdated:** `CAMModel.refreshLinkedGenerations()` flags a rest result when its pocket changes (the name is ignored) or is deleted; `ToolpathGeneration.isCurrent(for:)` then returns false. A deleted source is kept and reported as "no longer in the list".
- **Overlay:** the pocket's `ToolpathGeneration.restPath` is drawn on the canvas while the pocket is open and current (`CAMModel.showsRestAreas`).
- **Limits:** only line-to-line corners, only the pocket's outer boundary (islands ignored), regions are geometric (wall minus the tool circle), not the roughing actually cut.


## Setups

A setup is one way the stock is held (`Setup`): a name, an **angle** and an **axis** (`SetupAxis`, X or Y): the rotation of the stock about that horizontal machine axis. Top 0°, Front 90° about X, Bottom 180° about X or Y, Back 270° about X, Left 90° about Y, Right 270° about Y (`SetupFace`); a rotary axis later just means other angles. The axis of the Bottom is chosen: it is the axis the stock is flipped about, so the shapes mirror in Y (about X) or in X (about Y). Front, Back, Left and Right need a 3D model, so a project of 2D shapes only offers Top and Bottom.

- **Frame:** `SetupFrame.make(setup:stock:)` rotates the part by −angle about the stock's centre line (along X or Y) and puts z0 on the surface that faces up. STEP edges are mapped through it before they become contours (`STEPWorkspace.contours(for:frame:)`), so the engine sees what the machine sees and every Z field stays "depth below this setup's z0".
- **Stock:** the stock belongs to the setup (`Setup.stock`, never nil); the project has none of its own. A new setup starts as a copy of the active one's stock (`CAMModel.addSetup`), which is how one part is milled in two materials: each setup has its own z0, program and stock change. `CAMModel.stock(for:)` / `activeStock` give the one a setup is cut from: the frame (`setupFrame(for:)`), the facing of the whole stock (`ToolpathGenerator.prepare(stock:)`), the preview frames, the canvas stock (`canvasState.stock` follows the active setup, and the alignment pins are refitted to it; the pins are in every setup), the details panel's material (tool presets, feeds, Through stock) and the G-code header. The right-hand `PanelSetupDetails` shows for the selected setup: the object it cuts (picked from the imported ones, `CAMModel.setSetupObjects`) and its stock (`CAMModel.setSetupStock`). Changing a stock's shape or size outdates the results of the setups that depend on it (turned setups, whole-stock facing). A setup saved without a stock gets `StockMaterial.defaultWorkpiece`; `projectData.stock` only seeds the first setup of a project that has none. The part's position in another stock is not handled yet (it is centred: see the controller's offset).
- **Link:** `ToolpathData.setupID` (nil only in old projects: `CAMModel` puts those in the first setup). `CAMModel.setups` is never empty, and `toolpaths` is kept in setup order, so a setup's toolpaths are one contiguous run.
- **Results:** a toolpath's setup is part of its settings, so moving it outdates its result; turning a setup or changing the stock discards all results.
- **Preview:** drawn in the part's frame for Top and Bottom (Bottom is mirrored back in Y, or in X when flipped about Y); nothing for the side faces and no scrub for turned setups yet. Only the open toolpath is on the canvas (drawn in the one toolpath blue, `CAMSceneModel.Style.toolpathColor`): selecting a toolpath shows it, closing the panel removes it. The results of the other toolpaths are kept, for G-code, just not drawn.
- **All toolpaths:** the legend's Toolpaths row, labelled "All toolpaths" (`CAMModel.showsAllToolpaths`, session-only; the old hide-the-layer switch is gone). With none open it calculates every toolpath that has no current result (`generateAllIfNeeded`; the rest come from the cache) and draws all of them, from every setup; a setup that isn't the active one is drawn at 30% (`FaceToolpaths.opacity`: the orange mixed toward the background color, because the line renderer ignores alpha). Opening a toolpath still shows only that one. Results discarded by an edit are recalculated after a short pause (`scheduleAllToolpathsRefresh`).
- **Limits for now:** 2D shapes (SVG/DXF/Gerber) are cut from the Top only; whole-stock facing is not offered on the side faces; the side faces need rectangular stock. Stock is assumed to sit with its front-left corner at X = 0, Y = 0 (`StockMaterial.setupExtents`).
- **G-code:** one program per setup. `ToolpathGCodeBuilder.plan(…, setup:)` takes the setup to post; with several setups and no `setup` it refuses everything rather than merge them, because the stock has to be turned between setups.
- **Panel:** `PanelToolpaths` lists the active setup's toolpaths. The Setups dropdown lists the project's setups only (the setup's own stock in parentheses: "Top (Acrylic 3 mm)"); the "+" next to it opens Add setup (the faces the project doesn't have yet on its stock; the bottom turns the existing one when only the flip axis differs; "On different stock" lists every face and adds the setup with a copy of the project stock, then opens the stock panel) and Remove (asks first when the setup has toolpaths). Side faces are listed disabled when the stock isn't a rectangular block. Drag reorders inside a setup; "Move to setup" is in the row's menu.
