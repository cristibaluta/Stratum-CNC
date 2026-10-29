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
      │     bore / counterbore: target diameter / diameter · chamfer: width · facing: extension length
      │     (everything the library defines except direction, depths and what the app draws itself)
      │
      ├─ InspectorSection "Shapes"
      │  ├─ "Area" Selection / Whole stock    ← facing only
      │  ├─ "Selection is" + width note       ← slot only (OperationOptionsView, part .shapes)
      │  └─ "Selected": shapesLabel           ("N shapes selected", "Whole stock", orange "Click shapes to select")
      │
      ├─ InspectorSection "Tool"
      │  ├─ ToolPicker(toolpath.tool)
      │  ├─ InspectorNote(toolCompatibilityWarning)   ← tool can't do the operation
      │  ├─ InspectorNote(presetNote)
      │  └─ Spindle
      │
      ├─ InspectorSection "XY plane"          [OperationOptionsView, part .xyMovement]
      │  ├─ cut direction (climb / conventional)
      │  ├─ Feed rate
      │  ├─ stepOverRow (% of Ø + mm note)     ← if requirements.usesStepover, or facing
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
      │  ├─ rowPreview: generationStatus + "Preview" button   (disabled without shapes, and on a lead-in/entry conflict)
      │  └─ rowScrub: slider through the generated moves
      │
      └─ rowBottomBar: Delete · Next toolpath · Done (Esc)
```

## Data flow

```
CAMView.toolpathSettingsPanel(for:)
   │  toolpath:       Binding<ToolpathData>   (via binding(for:))
   │  stockMaterial / stockThickness          (camModel.selectedStockMaterial)
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
        (End Z, Stepdown and Stepover are marked in editedFields, so a later change of
         operation keeps them: see OperationDefaults)
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
