# Multi-object projects: plan

Goal: one project holds several objects. The Objects panel is where objects are imported and where setups are created. A setup can use one object or several combined. No compatibility with the current project format is needed.

## Decisions so far

- **Objects panel = file-manager tree**, one panel: Object > Setups. Toolpaths are *not* in the tree.
- **Toolpath panel** is separate, shows only the selected setup's toolpaths, one row each.
- **Position/scale/rotation** of an object is stored in the project (global). A setup may override it. No override means the global value is used.
- **Stock** is global (project) and can be overridden per setup (already the case today via `Setup.stock`).
- **Same face in several materials**: either two setups of the same face under one object, or a duplicate *entry* of the object in the list (same geometry, separate entry, own transform). Both are allowed; no special mechanism.
- **Combined setup**: a setup that includes more than one object. Listed under a "Combined" group, not inside one of the objects.
- **Right side**: object selected shows Position/Scale panel. Setup selected shows Material panel, with the Toolpaths panel below.
- **Duplicate entry** = same source, own transform. **STEP bodies** = one object each. **Fixtures group** only shown once pins exist.
- **No migration.** Old projects are not opened. Bump the project format version and refuse older files.

## Data model (target)

```
Project
  stock: StockMaterial                       // global
  objects: [ProjectObject]                   // library, one entry per imported/duplicated object
  setups: [Setup]                            // ordered = machining order
  toolpaths: [ToolpathData]

ProjectObject
  id, name
  source: asset reference (DXF / SVG / Gerber / STEP body)
  transform: Transform2D/3D                  // global position, scale, rotation

Setup
  id, name, angle, axis                      // as today
  stock: StockMaterial?                      // nil = project stock (as today)
  items: [SetupItem]                         // 1 = normal setup, >1 = combined

SetupItem
  objectID
  transformOverride: Transform?              // nil = use object's global transform

ToolpathData
  setupID                                    // as today
  targets: [Target]                          // each Target gets an objectID (shape belongs to an object)
```

Notes:
- A setup's "owner" in the tree is `items.first?.objectID` when it has one item. With several items it goes under "Combined".
- The existing `setupID` on toolpaths stays. `toolpaths(in:)` keeps working.
- Today `D2_Object` already holds `position`; the STEP side has `STEPBodyState` (position, face, scale). Both fold into `ProjectObject.transform`.

## Alignment pins

Today they are a parametric object (`AlignmentPinsData`: diameter, offset), fitted to the project stock, cut by toolpaths that target their circles.

Moving them *into* toolpaths does not fit: a toolpath targets shapes, and the pins are those shapes. Proposed instead:

- Pins belong to a **stock**, not to an object. They are a fixture: "Alignment pins" entry in the Objects tree under a **Fixtures** group.
- Global by default (fitted to the project stock). A setup with its own stock gets its own pins, or none.
- A setup can cut them like any shape; the toolpath references the pins' id (kept across rebuilds, as now).
- Do this last. Until then keep pins as they are and only make sure they still work with one object.

## Steps

Each step should leave the app building and usable.

### Step 1: Object model (done, not compiled yet)
- Added `ObjectTransform` (x, y, z, scale, rotation, face) and `D2_Object.transform` (read/write, same as setting position, width and rotation).
- Added `ProjectObject` and `CAMModel.projectObjects`: one read-only list over the 2D shapes and the STEP bodies, with the transform of each.
- Nothing stores or changes anything yet: edits still go through `D2_CanvasState` and `STEPWorkspace`, and the project is saved as before.
- Files: `CAM/Objects/ObjectTransform.swift`, `CAM/Objects/ProjectObject.swift`.
- Left for later: the project file still saves 2D shapes in `AssetData` and STEP bodies in `STEPBodyState`. Merging them needs `ProjectModel`, `ProjectData` and `AssetData`, which are not in the archive.

### Step 2: Setup items (done, not compiled yet)
- `Setup.items: [SetupItem]` (`objectID`, optional `transformOverride`). Empty means the setup includes every object, so every existing setup and one-object project behaves as before. Old saves still load (`items` is read if present).
- `CAMModel.placedObjects(in:)` and `resolvedTransform(of:in:)` in `CAM/Objects/SetupObjects.swift`: the one place for "override, else global".
- `setSetupObjects(_:to:)` and `setTransformOverride(_:for:inSetup:)` edit them; changing either outdates the setup's toolpaths.
- Not done: the canvas still draws every object at its global position. Drawing only the active setup's objects with their overrides touches `D2_Object` (it owns its position) and the STEP scenes, and is better done with step 4's transform panel.

### Step 3: Objects panel as a tree
- Replace the flat list with: Object > Setups. Hide the object level when there is only one object.
- Import (DXF, SVG, Gerber, STEP) lives here: "+" at the top.
- Selecting a setup makes it active; selecting an object isolates it on the canvas (others ghosted).
- Context menu: rename, duplicate entry, delete, new setup.
- Done when: a project with 2 objects shows both with their own setups; switching setups switches the toolpath list.

### Step 4: Right-side panels
- Object selected: Position / Scale / Rotation panel.
- Setup selected: Material panel on top, Toolpaths panel below.
- Transform panel for a setup shows the effective values, with a "Reset to global" action once overridden.
- Done when: editing the global transform moves the object in every setup that has no override; editing in a setup changes only that setup.

### Step 5: Toolpath panel, one row per item
- Remove the setups level from the panel (the tree owns it).
- Row: icon, name, tool diameter, final Z. Nothing else for now.
- Candidates to drop later: status badges, shape counts, inline buttons. Decide after seeing it.
- Done when: the panel lists the active setup's toolpaths and nothing else.

### Step 6: Per-setup stock
- Global stock panel stays. A setup's Material panel can switch to "Own stock".
- Already supported by `Setup.stock`; this step is mostly UI and clean-up.
- Done when: two setups of the same face under one object can use different materials.

### Step 7: Combined setups
- Multi-select objects (Shift-click in the tree or canvas) > "Combine into one setup…" (also in the "+" menu).
- Creates a setup with several `SetupItem`s, listed in the "Combined" group.
- Canvas: items laid out on the shared stock, draggable, with a collision warning.
- Stock size: follow the items' bounding box plus margin, or manual.
- Toolpath targets carry `objectID`, so one toolpath can cut shapes of different objects.
- Done when: two objects placed on one stock can be cut by one toolpath and exported in one file.

### Step 8: Alignment pins as fixtures
- Move pins out of the object list into the Fixtures group, tied to a stock, as described above.
- Done when: pins are refitted when the stock changes and can be cut from any setup that uses that stock.

### Step 9: Export and job overview
- G-code is one file per setup. A Job panel lists every setup with estimated time and an Export All.
- Warn when the same object is cut twice (own setup and a combined one).
- Done when: exporting a project with 3 setups produces the files in the right machining order.

## Rules to settle before Step 7

- All items in a combined setup share the setup's face and orientation. No mixing top of one object with bottom of another.
- Removing an object from a setup marks its toolpaths as outdated (as other edits do).
- Machining order across objects: the order of `setups` is the machining order; allow drag to reorder in the tree.

## Resolved questions

- **Duplicated entry**: shares the source geometry, has its own independent transform. A re-import of the source updates every entry that uses it.
- **STEP files with several bodies**: as today, each body is listed as its own object and manipulated separately. Each keeps its own state (position, face, scale).
- **Fixtures group**: appears only after "Add alignment pins" is used. It is not shown empty.

## Not verified yet

- The archive has no `ProjectModel`, `ProjectData` or `AssetData`, so the save format, and the "toolpaths in their own file" step, can't be written from here.
- Nothing has been compiled: there is no Swift toolchain in this environment.
