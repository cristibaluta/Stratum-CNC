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
      │
      ├─ InspectorSection "Shapes"
      │  └─ rowShapes
      │     ├─ "Area" Selection / Whole stock    ← facing only
      │     ├─ "Selected": shapesLabel           ("N shapes selected", "Whole stock", …)
      │     └─ InspectorNote(selectionHint)      ← what to click; the slot's text follows its source
      │
      ├─ InspectorSection "Operation"
      │  ├─ rowOperation: OperationPicker(operationKindBinding)   → renames via nextName() if !isNameCustom
      │  └─ rowOperationOptions: OperationOptionsView($toolpath)
      │     ├─ "Selection is" + width note        ← slot only
      │     ├─ ContourPicker (Side)               ← contour, chamfer
      │     ├─ ParameterFieldsView(formFields)    ← whatever the library defines for the operation
      │     │   (hidden: entry, contour.side, contour.tabs, contour.leadIn, contour.leadOut, pattern, slotting.depthPerPass,
      │     │    drilling.peckDepth, counterbore.depth, chamfer.params.side;
      │     │    the chamfer's "Chamfer" group is flattened)
      │     ├─ chamferDepthNote                   ← chamfer: "Depth = X mm for a Y° bit"
      │     ├─ LeadInOutRow ×2 (Lead-In, Lead-Out) ← contour: switch + summary + gear → LeadInOutEditor popover
      │     │                                        (explanation, to-scale LeadInOutDiagram, style / length / radius / sweep / feed)
      │     ├─ leadInConflictNote                 ← contour: lead-in + ramp/helix entry
      │     ├─ HoldingTabsButton                  ← contour
      │     ├─ patternRow (PatternPicker + patternDetail)   ← pocket
      │     ├─ stepOverRow (% of Ø + mm note)     ← if requirements.usesStepover, or facing
      │     ├─ stockToLeaveRows                   ← if requirements.usesAllowance (pocket; contour on a side)
      │     │   ├─ Stock to leave (mm)            ← walls, and a pocket's floor
      │     │   ├─ Finishing pass (toggle)        ← only while stock > 0
      │     │   └─ InspectorNote                  ← what is left, or a warning when stock ≥ pocket depth
      │     └─ rampingRow (Entry, Ramp angle)     ← if requirements.usesEntry
      │
      ├─ InspectorSection "Tool & feeds"
      │  └─ rowTool
      │     ├─ ToolPicker(toolpath.tool)
      │     ├─ InspectorNote(toolCompatibilityWarning)   ← tool can't do the operation
      │     ├─ InspectorNote(presetNote)
      │     ├─ Spindle
      │     ├─ Feed rate
      │     └─ Plunge feed                        ← always, also for drill / bore / thread mill
      │
      ├─ InspectorSection "Z levels"
      │  └─ rowDepth
      │     ├─ Start Z
      │     ├─ End Z                              ← counterbore: its own depth, shown as End Z
      │     │   └─ "Through stock" button         ← drill, bore, thread mill
      │     ├─ facing single-pass warning         ← facing without a stepdown, deep cut
      │     ├─ Depth per pass | Stepdown          ← slot has its own depth per pass
      │     ├─ Peck drilling + Peck depth         ← drill only
      │     └─ Clearance Z
      │
      ├─ InspectorSection "Preview"
      │  ├─ rowPreview: generationStatus + "Preview" button   (held back on a lead-in/entry conflict)
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
   └─ rowTool / rowDepth write the general fields directly
        (End Z, Stepdown and Stepover are marked in editedFields, so a later change of
         operation keeps them: see OperationDefaults)
```

## Where each value lives

| Value | Stored in | Notes |
|---|---|---|
| Stepover | `ToolpathData.stepOverPercent` | % of tool Ø; old projects stored mm and are converted on decode |
| Plunge feed | `ToolpathData.plungeRate` | also the ramp/helix feed |
| Stepdown | `ToolpathData.stepDown` | not used by slot |
| Slot depth per pass | `OperationSettings.slotDepthPerPass` | edited in Z levels |
| Peck depth | `OperationSettings.drillPeckDepth` (+ `drillUsesPecking`) | edited in Z levels |
| Counterbore depth | `OperationSettings.counterboreDepth` (positive) | shown as End Z, with the "−" in front |
| End Z | `ToolpathData.endZ` (negative) | typed as a positive depth |
