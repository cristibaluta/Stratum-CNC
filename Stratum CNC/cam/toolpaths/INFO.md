
PanelToolpathDetails
└─ GroupBox("TOOLPATH")
   └─ VStack (spacing: 16)
      │
      ├─ rowHeader                              [HStack]
      │  ├─ TextField(toolpath.name)             → sets isNameCustom = true on edit
      │  ├─ Spacer()
      │  ├─ expandToggle                         [Button: chevron.down]
      │  └─ doneButton                           [Button: "Done"]
      │
      ├─ Divider()
      │
      ├─ rowOperation                            [HStack]
      │  ├─ OperationPicker(operationKindBinding) → renames via nextName() if !isNameCustom
      │  └─ Text(hint)
      │
      ├─ Divider()
      │
      ├─ rowOperationOptions                     [VStack]
      │  ├─ OperationOptionsView(toolpath, expanded: isExpanded)
      │  │   └─ ParameterFieldsView(fields: formFields(...))   ← built elsewhere
      │  │       ├─ ChoiceControl / NumberField / IntField / ToggleField ...
      │  │       └─ .row / .group / .list nested blocks
      │  └─ NumberField("STEPOVER")               ← only if usesStepover
      │
      ├─ Divider()
      │
      ├─ rowTool                                 [VStack]
      │  ├─ ToolPicker(toolpath.tool)
      │  ├─ Divider()
      │  └─ HStack
      │     ├─ IntField("SPINDLE SPEED")
      │     └─ NumberField("FEED RATE")
      │
      ├─ Divider()
      │
      ├─ rowZ                                    [HStack]
      │  ├─ NumberField("START Z")
      │  ├─ NumberField("END Z")                  ← only if usesEndZ
      │  ├─ NumberField("STEPDOWN")                ← only if usesStepdown
      │  └─ NumberField("SAFE Z")
      │
      ├─ Divider()
      │
      └─ rowFooter                               [HStack, height 36]
         ├─ shapesLabel                           [Label: "N shapes selected"]
         ├─ Spacer()
         └─ (if targets not empty)
            ├─ Divider()
            └─ HStack
               ├─ generationStatus                [Label: error / outdated / success]
               └─ Button("Generate")               → onGenerate()

   .overlay: orange RoundedRectangle border, only while isPicking


CAMView.toolpathSettingsPanel(for:)
   │
   │  toolpath: Binding<ToolpathData>  (via binding(for:))
   │  siblingNames: Set<String>        (camModel.toolpaths, self excluded)
   │  isPicking / generation / isGenerating   (looked up from camModel by id)
   │  onGenerate: () -> Void  →  camModel.generateToolpaths(for:)
   │  onDone: () -> Void      →  camModel.selectedToolpathID = nil
   ▼
PanelToolpathDetails
   │
   ├─▶ rowHeader
   │      asks for: toolpath.name (custom get/set Binding)
   │      side effect on set: toolpath.isNameCustom = true
   │      also renders: expandToggle, doneButton  (no external data — use own @State / onDone)
   │
   ├─▶ rowOperation
   │      asks OperationPicker for: kind — via operationKindBinding, not $toolpath.operation.kind directly
   │         operationKindBinding reads:  toolpath.operation.kind, toolpath.isNameCustom
   │         operationKindBinding writes: toolpath.operation.kind, toolpath.name
   │                                       (name write also needs siblingNames + newKind.nextName(among:))
   │      asks Text for: hint  (derived from toolpath.operation.kind / slotSource)
   │
   ├─▶ rowOperationOptions
   │      asks OperationOptionsView for: $toolpath (whole binding, not just operation)
   │                                     expanded: isExpanded
   │         which itself asks toolpath.machiningOperation for: formFields(onChange:)
   │            → produces [SC.ParameterField], each already carrying its own onChange
   │         which it hands to ParameterFieldsView(fields:, expanded:, hiddenFieldIDs:, hiddenCaseIDs:)
   │            → ParameterFieldsView asks each field for its own value + onChange
   │              to build NumberField / IntField / ToggleField / ChoiceControl / .row / .group / .list
   │      asks NumberField for: $toolpath.stepOver   (only if usesStepover — conditional ask)
   │
   ├─▶ rowTool
   │      asks ToolPicker for: $toolpath.tool
   │      asks IntField for: $toolpath.spindleRPM
   │      asks NumberField for: $toolpath.feedRate
   │
   ├─▶ rowZ
   │      asks NumberField for: $toolpath.startZ            (always)
   │      asks NumberField for: $toolpath.endZ               (only if usesEndZ)
   │      asks NumberField for: $toolpath.stepDown            (only if usesStepdown)
   │      asks NumberField for: $toolpath.safeZ              (always)
   │
   └─▶ rowFooter
          asks shapesLabel for: toolpath.targets.count
          asks generationStatus for: generation  (passed-in, not toolpath-derived)
          asks Button for: onGenerate()  (passed-in callback, gated on isGenerating)
