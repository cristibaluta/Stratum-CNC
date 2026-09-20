# Roadmap: First MVP

**Import 2D SVG/DXF → create toolpaths (StratumCAM) → generate G-code in the Controller tab → send to the CNC → monitor the run.**

Companion to `controller/ROADMAP.md` (Makera command coverage). That one is about the machine side; this one is about the whole flow end to end. Paths below are relative to `Stratum CNC/`. Item tags: **[MUST]** blocks the MVP, **[SHOULD]** makes it usable, everything else is polish. Status comes from reading the code, not from running it. Nothing here has been checked on real hardware by the author of this file.

## The MVP flow

1. Import a 2D SVG or DXF into a project.
2. Define toolpaths on its contours: tool, depths, feeds, inside / outside / on-line. StratumCAM generates the geometry.
3. In the Controller tab, generate G-code from those toolpaths and preview it.
4. Position the job on the anchor, let the machine do Auto Z (and optionally level), send it.
5. Watch it run: progress, tool changes, errors, pause/resume.

**Acceptance job (MVP is done when this works, start to finish):** a DXF of a 60×40 mm plate with rounded corners and two Ø6 mm holes, one 3.175 mm flat end mill, cheap flat material. Two toolpaths: holes inside, outline outside. Import, generate, check the preview, air-cut it, cut it, and the part measures within ±0.1 mm.

**Not in the MVP:** STEP import, Gerber/PCB (importer exists, leave it), 3D toolpaths, laser, thread milling.

---

## Where things stand

| Stage | State | What's there / what's not |
|---|---|---|
| Import | Works, with gaps | SVG, DXF and zipped Gerber parse into canvas objects that can be moved, scaled, rotated and persisted per project. No unit handling, no layer control. |
| Toolpath setup | Half there | List UI, feeds, depths, ramping editor, drag-reorder. Can't bind a toolpath to a contour, can't pick a tool, not persisted. |
| Toolpath → G-code | **Stubbed** | `ToolpathGCodeBuilder.generate` does the work, then returns `""`. |
| Controller: generate | **Not wired** | "Use from CAM" button has an empty action. |
| Preview | Works | Parser, 3D canvas, heightmap carve, scrubber, tool marker. |
| Send | Built | Upload to SD, G54 origin from the canvas XY offset, Auto Z, Auto level, `play`. Not hardware-verified (see controller roadmap notes). |
| Monitor | Mostly built | Progress bar, executing line, live tool position, alerts. No "job finished", no time remaining. |

### The breaks in the flow

These are the concrete reasons the flow doesn't run today.

- **B1. G-code generation returns an empty string.** In `cam/toolpaths/ToolpathGCodeBuilder.swift` the flatten, world-transform and offset steps run, then the `GCodeGenerator.generate(...)` call is commented out and the function returns `""`.
- **B2. The Controller tab can't ask for it.** The "Use from CAM" button in `controller/ControllerView.swift` has an empty action (its comment refers to `camModel.files` / `svgPaths`, an API that no longer exists). `GCodeStore.generateGCode(for:canvasState:)` has no callers, handles one toolpath only, and only `print`s its errors.
- **B3. Nothing ever sets `ToolpathData.target`.** Generation throws `.noTarget` without it. No UI turns the canvas's selected contour (`canvasState.selectedPaths`) into a toolpath target, and `target` holds a single contour.
- **B4. Toolpaths are never saved or restored.** `CAMModel.onToolpathsChanged` is wired up in `ProjectModel` but nothing calls it, so `toolpaths.json` is never written. On load, `toolpaths.json` is decoded into `ProjectModel.toolpaths` and never reaches `camModel.toolpaths`.
- **B5. The tool picker is empty.** The `Menu` items in `cam/toolpaths/ToolPicker.swift` are commented out. New toolpaths start from placeholder values (feed 0.1, plunge 0.1, stepdown 0.1 mm, 1200 RPM, end Z −1) that aren't derived from the tool or material.
- **B6. No toolpath preview in the CAM tab.** `D2_CanvasRenderer` creates `toolpathsLayer` and never draws into it.
- **B7. Imports ignore units.** No DXF `$INSUNITS`, no SVG `width`/`height` units or px→mm. Geometry is used 1:1 as millimetres.
- **B8. Two possible offset implementations.** The app has its own `PolygonOffset` (per-edge offset-and-intersect; its own comment says it doesn't handle self-intersections or islands). What StratumCAM offers isn't visible from the app.

---

## Milestones

- **M1 — "G-code appears":** Phase 0, 2.1, 2.3, 3.1–3.4, 4.1–4.2. One contour in, G-code in the Controller preview.
- **M2 — "First air cut":** 5.1–5.3, 7.1. The M1 program runs on the machine above the material.
- **M3 — "First real cut":** 1.1–1.3, 2.2, 2.4, 2.6, 5.4, 6.1, 8.1. The acceptance job, with saved projects and a finish notification.
- **MVP:** the remaining [MUST] items, then the acceptance job on a clean checkout.

---

## Phase 0 — Decide and audit (unblocks everything)

- [ ] 0.1 **[MUST]** Audit StratumCAM's public API against what the app needs. The library source isn't in the project; the app visibly uses only `EntityChainer.chain` (DXF and Gerber importers) and the commented-out call `GCodeGenerator.generate(subpaths:units:safeHeightZ:passDepths:feedRateCut:feedRatePlunge:spindleSpeed:ramp:preamble:)`. For each capability, write down whether it's *library*, *app* or *missing*: inside/outside offset (with holes and islands), depth passes, ramp entry (linear/helix), lead-in/out, tabs, G2/G3 arc output, tool change / M6, header comments.
- [ ] 0.2 **[MUST]** Give `RampingSettings` one home. It's defined in the app (`cam/toolpaths/ramping/RampType.swift`) and was passed to the library call above. If the library has its own type or expects different fields, that's a likely reason the call got disabled.
- [ ] 0.3 **[MUST]** Pick one offsetting implementation (library or `PolygonOffset`) and delete the other.
- [ ] 0.4 **[MUST]** Write down and test the coordinate convention. Assumed today: canvas Y-up, XY (0,0) = stock lower-left corner (as `StockLayer` draws it), Z0 = stock top. `jobOriginCommands` puts G54's XY origin at the canvas XY offset, so CAM output is only right if this holds. Check the SVG Y-flip too (`SVGImporter`), using an asymmetric shape like the letter "F". Confirm that Auto Z's zero (`G10 L20 P0 Z0` at the trigger point, no plate-thickness offset yet, see controller roadmap 4.2/4.3) actually equals "stock top".
- [ ] 0.5 Decide, and record the answers here:
  - Are pockets in the MVP? (`stepOver` exists but contours don't use it.)
  - Are holding tabs in the MVP? (Through-cuts usually need them.)
  - One tool per job for hardware testing, or multi-tool with the ATC?

## Phase 1 — Import (SVG / DXF)

- [ ] 1.1 **[MUST]** Read units. DXF `$INSUNITS`; SVG `width`/`height` units against the viewBox (px at 96 dpi, mm, in). Show the detected unit at import and let the person override it.
- [ ] 1.2 **[MUST]** Show the imported size after import and warn when it's implausible (larger than the stock, or under 1 mm).
- [ ] 1.3 **[SHOULD]** Place objects on the stock at import. Today an object keeps its file coordinates (`position` = its bounds minimum). Add "center on stock" and "align to stock corner".
- [ ] 1.4 **[SHOULD]** Contour quality feedback. Flag open contours, and report skipped entities (DXF text and dimensions draw nothing today). Make it obvious which closed contours are outer boundaries and which are holes.
- [ ] 1.5 **[SHOULD]** SVG coverage against real files (Inkscape, Illustrator, Fusion): nested groups and transforms, `<use>`, rect/ellipse, stroke-only vs fill, hidden layers.
- [ ] 1.6 **[SHOULD]** DXF coverage: LWPOLYLINE bulges, SPLINE, INSERT/blocks, layer list with show/hide.
- [ ] 1.7 Re-import that keeps toolpath targets. `PathSelection.pathIndex` shifts when contour order changes; the builder already reports `.pathIndexOutOfRange`, so surface that in the UI instead of failing at generate time.
- [ ] 1.8 Drag-and-drop import.

## Phase 2 — Toolpath definition

- [ ] 2.1 **[MUST]** Bind contours to toolpaths (B3). "Assign selected contour(s)" writes `target` from `canvasState.selectedPaths`. Selecting a toolpath highlights its contour. Either make `target` a list, or make "create toolpath from selection" create one toolpath per contour.
- [ ] 2.2 **[MUST]** Real tool picker (B5). List `ToolLibrary`, and on pick fill feed / plunge / RPM / stepdown from `Tool.parameters` for the stock's material (`ToolCuttingParameters`). The person can still override.
- [ ] 2.3 **[MUST]** Defaults and validation. End Z below start Z, feed and stepdown above zero, safe Z above the top, depth within the tool's flute `length`, end Z against the stock thickness (warn on a through-cut past the bottom), and an inside contour narrower than the tool.
- [ ] 2.4 **[MUST]** Persist toolpaths (B4). Fire `onToolpathsChanged` from a `didSet` on `CAMModel.toolpaths` (debounced), and load `toolpaths.json` into `camModel.toolpaths`. Close and reopen a project to test.
- [ ] 2.5 **[SHOULD]** Per-toolpath enable/disable, duplicate, delete.
- [ ] 2.6 **[SHOULD]** Draw the toolpath in the CAM tab (B6): the tool-radius-compensated path into `toolpathsLayer`, from the same geometry the generator uses so the preview and the cut can't disagree. Show direction and entry point.
- [ ] 2.7 **[SHOULD]** Cut direction (climb / conventional), start point, and stock-to-leave with a finishing pass. Only if the library supports them (0.1); none are in `ToolpathData` today. Hide `stepOver` for contour types.
- [ ] 2.8 Holding tabs for through-cuts (see 0.5).

## Phase 3 — Generation with StratumCAM and program assembly

- [ ] 3.1 **[MUST]** Make `ToolpathGCodeBuilder.generate` actually produce G-code (B1): flatten, world transform, offset, depth passes, ramp entry, library call.
- [ ] 3.2 **[MUST]** Build a whole program from all enabled toolpaths, not one. Preamble once (`G21 G90 G17 G54`, retract to safe Z), each toolpath's body, one shutdown (`M5`, retract, park, `M30`). Suggested entry point: `generateProgram(toolpaths:canvasState:stock:)`.
- [ ] 3.3 **[MUST]** Emit the header the Controller already reads. The `MakeraCAMHeaderParser` shape is `; Stock Size: X(X) * Y(Y) * Z(Z) mm`, `; Material:`, a `; Tool List` with `; T1-3.175*12mm Flat End(Metal)` lines, and a `; Path List`. It drives the run sheet's stock and tools sections and the tool-to-spec assignment. That parser drops tip angle and length, so a V-bit previews as a flat tool. Either extend it or add a Stratum-specific header parser (the `GCodeHeaderParser` protocol makes it a drop-in) that round-trips tool type, tip angle, and length. Round-tripping also fills the gap where `ToolSpec` has no length field.
- [ ] 3.4 **[MUST]** Tool numbers and changes. One T number per distinct tool, `T# M6` at each change (the analyzer and viewer split the program into sections by these), `M3 S…` with a spin-up dwell. The tool-change alert for the manual case already exists.
- [ ] 3.5 **[SHOULD]** Emit G2/G3 arcs instead of flattening everything to G1 at 0.05 mm (`flattenTolerance`); smaller files and smoother motion.
- [ ] 3.6 **[MUST]** Deterministic output: the same input gives byte-identical G-code, so golden-file tests work (8.1).
- [ ] 3.7 **[SHOULD]** Estimated cutting time from the generated program (reused by 6.2).

## Phase 4 — Controller tab: generate, review, preview

- [ ] 4.1 **[MUST]** Wire "Use from CAM" (B2) to the Phase 3 program builder. Add "Regenerate from CAM" while a program is loaded. Show `BuildError` messages in the UI instead of printing them.
- [ ] 4.2 **[MUST]** Name the program. `NCFileDocument.load(from: String)` sets the file name to "From CAM", and that becomes the SD-card file name. Use `<project>-<yyyyMMdd-HHmm>.nc`.
- [ ] 4.3 **[SHOULD]** Stale marker. Store a hash of toolpaths, objects and stock with the generated program; when CAM changes afterwards, show "G-code out of date, regenerate".
- [ ] 4.4 **[SHOULD]** Export the `.nc` to disk. The sandbox entitlement is `files.user-selected.read-only`; saving needs read-write.
- [ ] 4.5 Tool marker at real size and shape from the active tool. A solid-tool patch exists separately; merge it, then re-check V-bit and ball-nose once 3.3 carries the tip angle.

## Phase 5 — Position, send, run (mostly built; harden it)

Already in place: machine discovery and connect, upload to SD (`GCodeUploader`), G54 origin from the canvas XY offset (`G10 L2 P1`), Auto Z before run, Auto level (`G32`) before run, `play`, pause / suspend / resume / stop, and the `MachiningRunSheet` review.

- [ ] 5.1 **[MUST]** Verify on real hardware. The framed-protocol payloads for file start and MD5 are marked in the controller roadmap (1.2) as a best-effort reconstruction, so check them against a packet capture. Also confirm `play <path>`, `goto`, and the assumption that the probe's "ok" waits for the probe cycle to finish (controller roadmap 1.5, 4.1).
- [ ] 5.2 **[MUST]** Anchor position in machine coordinates. `jobOriginCommands` uses the XY offset as-is, which assumes the anchor's inside corner is machine XY (0,0). Add a machine profile (anchor corner position, axis signs); the doc comment on that function names it as the one place to change.
- [ ] 5.3 **[MUST]** Air-cut mode: run with a positive Z shift on G54 so the first run of any new program never touches material. `jobOriginCommands` deliberately leaves Z alone today, so this needs a Z path alongside the Auto Z step.
- [ ] 5.4 **[SHOULD]** Make the run sheet's checks blocking, not advisory. `canStartJob` only checks connected / not uploading / has lines, while an unassigned tool shows an orange "Not assigned" and still starts.

## Phase 6 — Monitor

Already in place: progress bar with line, percent and elapsed (controller roadmap 1.4), executing-line highlight, live tool position in the 3D view, alerts for tool change / pause / alarm / error / lost connection / suspended job.

- [ ] 6.1 **[MUST]** "Job finished" and "job failed" notifications. `MachineAlert.Kind` has no completion case; detect the run-to-idle transition at the end of the file and post it.
- [ ] 6.2 **[SHOULD]** Time remaining. The machine's percent is by bytes read, not by time, so estimate from the program (3.7) plus elapsed.
- [ ] 6.3 **[SHOULD]** Feed and spindle override during a run (controller roadmap 2.4).
- [ ] 6.4 **[SHOULD]** Run log kept with the project: program, start/end, result, alerts raised.
- [ ] 6.5 **[SHOULD]** Reconnect to a job that kept running after the connection dropped (the lost-connection alert says it should). The status report has no file name, so decide how to match it to the loaded program.

## Phase 7 — Safety and preflight

- [ ] 7.1 **[MUST]** Bounds check before sending. The program's XY extents, plus the job offset, must sit inside the stock (warn) and the machine's work area (block); minimum Z must not go through the bottom. There's no machine work-area model in the app today, so this depends on the 5.2 machine profile.
- [ ] 7.2 **[MUST]** Lint at generation time (with 2.3): depths, feeds, safe-Z clearance, tool actually assigned for every T.
- [ ] 7.3 **[SHOULD]** Make the Stop semantics explicit in the UI: Stop is a `^X` soft reset (not resumable, typically leaves Alarm); Pause is the feed hold; Suspend is the resumable console command (controller roadmap 1.3, 1.6). The graceful `abort` is still an open option.

## Phase 8 — Quality and shipping

- [ ] 8.1 **[MUST]** Add a test target (the project has none). Cover: importer fixtures (bounding box and units), `passDepths`, offsetting, generator golden files, generated G-code parsed back through `GCodeParser` to check bounds against the design, and an end-to-end run through `MockMachineSimulator`.
- [ ] 8.2 **[SHOULD]** Check the acceptance-job DXF and SVG into the repo as sample projects.
- [ ] 8.3 **[MUST]** Confirm `Info.plist` has `NSLocalNetworkUsageDescription` (and Bonjour entries if used). It isn't in the project files; discovery is UDP broadcast plus TCP under the sandbox (`network.client` and `network.server` are present).
- [ ] 8.4 Release basics: signing, notarization, version number.

---

## After the MVP

Pocketing and facing (if 0.5 says no), drilling with peck cycles, V-carve / engraving, tabs (if 0.5 says no), STEP import, Gerber/PCB milling, laser mode (controller roadmap 2.3), thread milling, polished multi-tool ATC jobs, material-removal simulation in the CAM tab, the remaining probing workflows (controller roadmap 4.2–4.4), Wi-Fi setup panel (controller roadmap Phase 3).
