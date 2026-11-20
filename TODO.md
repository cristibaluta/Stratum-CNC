# TODO: what is still open

Compiled on 2026-11-20 from `ROADMAP.md`, `PAUSE_RESUME_PLAN.md`, `3D-Probing-Plan.md`, `STEP_Edge_Parser_Plan.md` and `Stratum_Code_Review.md` (plus the "limits" in `INFO.md` and the open item in `Coordinates.md`).

**How it was checked.** Every item in sections 1 to 6 was looked up in the app source in the archive (read or grepped); the file or symbol is given so you can verify it. Nothing was compiled or run. StratumLink, StratumCAM and SwiftSTEP are not in the archive, so what lives there is in section 7, unchecked. Done items were dropped (section 8 lists what was confirmed done).

---

## 1. Fix first: data loss and machine safety

- [ ] **A failed load can wipe the project.** `ProjectModel.init` catches a decode error of `project.json`, prints it and continues with an empty `ProjectData`; the next autosave overwrites the file. `ProjectsStore.loadProjects` logs and continues the same way, and `ToolsStore.init` sets `tools = []`. There is no `loadFailed` flag, no `.bak` copy, and `ProjectData` has no `schemaVersion` (only `ToolLibrary` has one). `toolpaths.json` was not re-checked.
- [ ] **Stop can do nothing right after `play`.** `JobCoordinator.stop()` returns early unless `jobRunner.isActive` or the last status is busy, and status lags by about a second. Track "play sent, awaiting status" and soft-reset in that window (or whenever Stop is pressed while connected).
- [ ] **Releasing a jog does not cancel motion already sent.** `JogDirection.stopAll()` only clears `held` and stops the timer. Send a realtime cancel / feed hold on release, and shorten chunks at high hold feed.
- [ ] **Resume-from-line can silently resume from the wrong place.** `JobCoordinator.resume(fromLine:)` sends `goto` only if `lastUploadedRemotePath != nil && status?.isHeld == true`; otherwise it skips the `goto` and resumes with no message. Make it return a result, confirm the Pause state first, and show an error when `goto` can't be sent. It also never checks that the uploaded file is the program on screen.
- [ ] **Bookmark entitlement missing.** `Stratum-CNC.entitlements` has sandbox, user-selected read-write and network client/server, but not `com.apple.security.files.bookmarks.app-scope`, which `ProjectBookmark` needs after a relaunch. (The Local Network usage string is set in the build settings, so that part is fine.)
- [ ] **No work-envelope / soft-limit check** for jogging or the job origin. Only the probe result has a bed check (`ProbeResult.checkBed`).
- [ ] **Save failures are invisible.** `ProjectModel.saveIfNeeded` is `try? save()`. Add an error surface, and consider a versioned backup. The metadata and toolpath writes are still two separate writes.
- [ ] **Auto Z is still crude.** `JobCoordinator.autoZeroProbe` probes 10 mm down at the current XY and zeroes at the trigger point (no probe-plate thickness). At least say so in the UI.
- [ ] **Alarm during a job ends progress tracking.** In `JobProgress.observe`, `.alarm` (like `.stopped` and `.interrupted`) returns `.unchanged` for all later status.
- [ ] **Metal pipeline failures are silent.** `MetalRenderer` creates its pipelines with `try?`, so a shader failure gives a blank canvas without a message.

## 2. Pause / suspend / resume

- [ ] **Step 7, verify before resuming.** Not in the code: a resume review sheet (resume line, canvas preview of the completed portion, WCS and position check) and the optional "air cut first".
- [ ] **`goto` path sends no preamble.** `resume(fromLine:)` only seeks and resumes, so Z has to be lifted by hand. The generated-file path (`resumeJobWithGeneratedFile`, used by the bit-change flow) does include it.
- [ ] **Program fingerprint is never compared.** `JobProgress.matches(fingerprint:)` exists but has no caller (see section 6).
- [ ] **Offer Resume on launch.** Only the wrench button appears when a saved job is resumable (`ControllerView`); there is no prompt on launch.
- [ ] **Not stored in `JobProgress`:** active WCS (G54 to G59), tool number, stock.
- [ ] **Resume preamble gaps:** tool length offset (G43/G49), cutter compensation (G41/G42), G10, G93, and canned-cycle state (cycles G81 to G89 only produce a warning in `GCodeModalState`). `travelZ` is the program's highest Z in work coordinates, so a re-probe after a bit change can leave it below the material. Back-up distance counts arcs as chords. A tool length offset delta for a different tool changed by hand is not handled.
- [ ] **Suspend:** park position is `G28` only (setting: "Park after suspending a job", `SettingsView`); no configurable safe Z. No automatic triggers into suspend or the bit-change flow (spindle temperature, alarms; nothing in `Controller` reads temperature).
- [ ] **Step 8, remove the old path.** `JobCoordinator` still calls `session.suspendJob()` so the library's alert policy ignores our own suspend. The pause/suspend/resume/stop and `MachineAlert` code in StratumLink `MachineSession` is still to be removed (package not in the archive). Update `README.md` / docs afterwards.
- [ ] **Mismatch check after resuming a resumed file** (`BitChangeSheet.swift:417` in the review) was not re-checked; it is moot until the fingerprint comparison exists (section 6).

## 3. 3D probing

- [ ] **Stock size check.** Compare the measured size with the stock in the library and warn above a tolerance (default 1 mm). `ProbeSheet` says "the probe does not use the stock".
- [ ] **Origin vs the origin the loaded program expects** (plan 7.4). Nothing in `Controller/Probing` reads `FusionHeaderParser` / `MakeraCAMHeaderParser`; the sheet only warns when the numbers differ from the lines sent (`isCarried(by:)`).
- [ ] **Rotation check** (plan 7.9): two touches along one edge, warn above about 0.3°.
- [ ] **Probe-triggered state** in the checklist is manual ("triggers when I touch the tip"); nothing reads the probe pin from the status.
- [ ] **Open questions that need the machine or StratumLink** (plan section 13): how probe results are delivered, exact `G38.x` behaviour and error output, wireless probe wake-up and ball offset, whether Z0 survives the tool change (7.5), whether `G10 L2` survives a power cycle, what `CNC.probe` and `zeroCommand` emit.
- [ ] **Machine test order** from the plan (trigger by hand, Z only, single edge, corner, centre, circle with a pin of known diameter) was not verifiable.
- [ ] **Out of scope for v1, still not there:** tool-length / tool-setter probing, vise or fixture probing, rotation compensation, probe history, pocket probing, starting outside the stock.

## 4. CAM and STEP (roadmap)

**Picking from the model**
- [ ] Round faces: a click inside a hole or on a cylinder wall. `STEPFacePicker` handles flat faces only ("A hole or a round wall is picked through its circle or its edges").
- [ ] Features as one object (pockets, bosses) and automatic recognition from the face topology (plan steps 7 and 8: convexity, hole and pocket classification, a Holes / Pockets list). The app has `STEPDisplayGeometry+Feature`, but that only classifies a selection of edges.
- [ ] Face selection with a ray pick and BVH, hover highlight, and per-face data panel (plan step 7). Current face picking works from coplanar triangle patches instead.

**Holes**
- [ ] Helical milling as an operation (the operation list has contour, pocket, pocket 3D, facing, slot, engrave, drill, counterbore, bore, thread mill, chamfer).
- [ ] A "Drill holes" shortcut that offers the operation straight from a selection (today only "Select similar" exists).
- [ ] Circles split into two arcs, and holes along axes other than Z (`HoleCircle` is "a full circle in a horizontal plane").

**Operations and checks**
- [ ] Automatic machinable regions (pockets and stock exterior from the model).
- [ ] Collision and gouge checks (tool, holder, clamps, fixtures). Nothing in the app.
- [ ] Feed / speed advisor in the toolpath panel. `ChipLoadAnalysis` (chip thinning, heat, heavy chip) is only used inside the feed calculator popover; there is no automatic warning on the toolpath, and nothing on spindle load.
- [ ] Total time across all toolpaths in CAM. The per-toolpath estimate ("Estimated time" in the panel) and the program estimate in the G-code viewer exist.
- [ ] **Spring passes** (rerun the final pass at the same depth and offset, with no extra stock, to clear tool deflection). Not found; the existing `finishingPass` is something else: it removes the stock left by `stockToLeave`. A spring pass is also called a skim or clean-up pass.

**Known limits listed in `INFO.md` (not re-verified)**
- [ ] Setups: 2D shapes (SVG/DXF/Gerber) cut from Top only; whole-stock facing not offered on side faces; side faces need rectangular stock; no scrub or preview for the side faces; stock assumed at X = 0, Y = 0.
- [ ] Rest machining: only line-to-line corners, only the pocket's outer boundary (islands ignored), regions are geometric rather than the actual roughing.

## 5. Quality and polish

- [ ] **Tests.** The test target holds only `SVGFlattenerTests.swift`. Start with the pure logic: `GCodeModalState`, `ResumePreamble`, `ResumePointResolver`, `BitChangeFlow`, `JobProgress`, `ProbeCycleBuilder` (signs, centre maths), `GCodeTimeEstimator`, bounds.
- [ ] **Undo / redo.** No `UndoManager` anywhere; deleting an object or toolpath is permanent apart from autosave.
- [ ] **User-visible errors** for load, save, import and generation failures (mostly `print` today).
- [ ] **Stepover label.** Three TODOs still ask whether stepover is a percentage of radius or diameter (`SC.Pockets+FormFields.swift:31`, `SC.EntryStrategy+FormFields.swift:58`, `OperationOptionsView.swift:794`). Settle it with a test; a mismatch means 2x.
- [ ] **Placeholder warning texts.** `ToolpathGenerator` returns the string "TODO" for `islandBelowFloor` and `depthExceedsFluteLength`.
- [ ] **`GerberImporter.parse(url:)` calls `fatalError`**, so a caller through the `Importer` protocol would crash.
- [ ] **`NCFileDocument.rebuildToolpath`** re-parses the whole file on each line edit (the author's TODO is still there).
- [ ] **Smaller things in the review:** each `ProjectModel` has its own `ControllerModel` and session (leaving a project mid-job drops the connection); `JobProgressStore` and `lastUploadedRemotePath` are one global record for all projects and machines; step jog relies on `$J` being relative; game controller stick values never zeroed and `buttonPresses` is a single `AsyncStream`.
- [ ] **Importers** (from the review, not re-checked in depth): no `$INSUNITS` handling is visible in `DXFImporter` (may live in the DXF library); DXF splines, INSERT/blocks, HATCH dropped silently; Gerber has no aperture macros, step-and-repeat or aperture transforms; the imported file is copied into the project before parsing, so a parse failure leaves an orphan asset.

## 6. The plans say "done", the archive disagrees

- [ ] **Bit-change fingerprint warning.** `PAUSE_RESUME_PLAN.md` step 6 says a warning is shown when the loaded program's fingerprint differs from the one saved with the job. `BitChangeFlow` has no such warning, and `JobProgress.matches(fingerprint:)` is never called.
- [ ] **Unit tests listed as done** are not in the archive: `JobProgressTests`, `ResumePreambleTests`, `ResumePointResolverTests`, `BitChangeFlowTests`, plus the STEP and probing tests the plans describe. Either they live on another branch or they were lost.
- [ ] **`ProjectPathsRegressionTests` / `ProjectPersistenceTests`** (said not to compile in the plan) are not in the archive either.

## 7. Can't be checked from this archive

**StratumLink** (items from the Nov 2 review; some may be fixed since)
- [ ] The upload payload layout is a "best-effort reconstruction": capture a real upload from the official controller and diff it before relying on it.
- [ ] Uploader: any line containing "ok" completes verifying; no timeout in `.transferring` / `.verifying`; broad error keywords fail an active upload.
- [ ] No connect timeout (`.waiting` ignored); protocol detection is only three 0.15 s probes; `sendRealtime` returns false before detection finishes.
- [ ] Job runner has no ack timeout; pre-run steps without Auto Z / Auto Level are not acknowledged.
- [ ] Job overwrites G54 XY with `originOffset`; check what `jobOriginCommands` and `zeroCommand` really emit (also open in `Coordinates.md`).
- [ ] Connection-lost alert misses a clean socket close; discovery never ages machines out, always lists the mock machine, and breaks on a comma in a name.
- [ ] Downloads accept a missing MD5; QuickLZ is detected but unsupported; tool-change alert detection is a keyword heuristic (capture the real M6 text).
- [ ] `CNCCommand+Builder.swift:113` uses `fatalError` for an invalid M497 status.
- [ ] Machine-only checks from the pause plan: `goto` with `suspend` vs feed hold, modal state after the jump, behaviour after a soft reset, `M491` leaving work Z valid, Idle reported only after a measurement finishes.

**StratumCAM**
- [ ] No parameter validation in `SCEngine.generateToolpaths` (add one `preflight` that throws).
- [ ] G-code writers: `Int(feed.rounded())` traps on NaN/inf, zero feed writes `F0`, `number()` has no `isFinite`, names and comments are not sanitised.
- [ ] `SCPostEngine` loses the tool and returns an error string as G-code.
- [ ] `offsetContour` / `exactOffsetContour` return the unoffset geometry when everything collapses.
- [ ] Likely wrong output: chamfer offset, allowance with a narrow feature, pocket rings capped at 500, boring width, drilling re-plunge and bounding-box centre, thread milling centre, climb/conventional ignoring M4, entry at Z0 without clearance, holding-tab width and ramp, open contours with inside/outside, `EntityChainer` ordering, `calculateZPasses` with a tiny stepdown, ellipse sampling.
- [ ] Two G-code writers with different gaps; timing logs printed by default (`OffsetTiming.isEnabled`); `SCPostEngine` has no timeout; everything assumes mm; TODO/FIXME markers listed in the review.
- [ ] CAM feature wishes from the review: V-carve and area engraving, chip-break drilling (G73), spot drilling and tapping, tool-change and toolpath ordering, stock-aware rapids, tab shapes and automatic placement, G41/G42 output, coolant and air blast, G53 retract before tool change, multiple work offsets, collision simulation, inch/mm switching, DXF splines and blocks.

**SwiftSTEP** (`STEP_Edge_Parser_Plan.md`)
- [ ] Step 4b: freeform shapes not showing or selecting (B-spline forms without explicit knots, COMPOSITE_CURVE, nested trims, vertex tolerance, freeform surfaces). The app shows an "N skipped" count; a distinct colour for skipped edges was not found.
- [ ] Step 9: assemblies. The app imports through `STEP.Assembly`, so this may already be done in the package.
- [ ] Hardening: a corpus of real CAD exports, 50 to 100 MB memory and frame-time profiling, and GPU verification of steps 5 and 6 (the plan marks both "unverified on GPU").

## 8. Checked and already done (dropped from this list)

- Probing: Z surface, points, boss/pocket corner and centre, nine-point picker, apply with canvas-offset sync, revert, move over the origin, park position, bed check, dry run, `G92.1`.
- Resume: job coordinator, persisted `JobProgress`, safe suspend, modal-state scan and preamble, resume file, restart points, bit-change sheet with start of pass / back up / exact line.
- STEP: display modes (wireframe, hidden edges, shaded, shaded + edges), flat-face picking, "Select similar" for holes, skipped-edge count.
- Time: per-toolpath estimate in the panel and a program estimate in the G-code viewer.
- Local Network usage description (set in build settings).
