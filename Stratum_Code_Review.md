# Stratum CNC – Code Review

Covers the three archives: **Stratum CNC** (macOS app, ~45k lines), **StratumCAM** (toolpath + G-code library, ~13k lines) and **StratumLink** (Makera machine connection, ~4k lines).

**How this was done.** I read StratumLink (connection, session, upload, download, job runner, discovery, bounds, alerts) myself. Two reviewers covered StratumCAM and the app; the app review skimmed some areas (listed under Coverage). Claims marked *verified* I checked against the code myself. Nothing was compiled or run: the archives contain no Xcode project, `Package.swift` or `Info.plist`, and nothing was tested against a real machine. *Suspected* means it depends on code I did not read or on firmware behaviour.

## Overall impression

The architecture is sound and the code is unusually well commented. The StratumCAM model layer is clean, and the resume-after-bit-change design and the session/alert layer show real safety thinking. The weak spots are not style:

1. **No tests anywhere** (verified: no test target or test files in any of the three archives).
2. **Silent failure paths that can lose user data.**
3. **Machine-control paths where Stop can do nothing, or a jog keeps moving after release.**
4. **No input validation in the CAM engine**, so bad parameters become wrong cuts instead of errors.
5. **The file-upload protocol is explicitly a reconstruction**, not confirmed against hardware.

## Fix these first

1. **A failed load can wipe the project** (app, High, verified). `ProjectModel.swift:128-136` catches a decode error, prints it, and continues with an empty `ProjectData`. The next autosave (30 s), close or quit overwrites `project.json` with the empty data. `loadProjectData` does the same for `toolpaths.json`. `ProjectsStore.swift:77-81` does it for the project index, so one bad `projects.json` loses every project entry and bookmark. *Fix:* keep a `loadFailed` flag and refuse to save, copy the file to `.bak` before any overwrite, and add a `schemaVersion` to `ProjectData` (only the tools library has one). `ToolsStore` has the same empty-on-failure behaviour.
2. **Stop can be a no-op right after `play`** (Link/app, High, verified in `MachineSession.stopJob`). It only soft-resets if `jobRunner.isActive` or the last status was busy. Status is polled at 1 Hz, so for up to about a second after `play` the last status is still Idle. Stop clears `pendingPlayPath`, sees nothing to abort, and returns, and the job starts anyway. *Fix:* track "play sent, awaiting status" and send the soft reset unconditionally in that window (or whenever Stop is pressed while connected). The app's `JobCoordinator` has the same pattern (`:563-567`).
3. **Releasing a jog does not cancel motion already sent** (app, High, verified: `JogDirection.stopAll()` only clears state and stops the timer). Chunks already on the wire keep running: about 2.5 mm at 750 mm/min for the first 0.2 s chunk, plus a catch-up chunk of up to 0.25 s. It scales with the user-adjustable hold feed. Nothing sends a jog cancel or feed hold on release, and there is no soft-limit check. *Fix:* send a realtime cancel (`!` or the firmware's jog cancel) on `stopAll()`, and shorten chunks at high feed.
4. **Resume-from-line can silently resume from the wrong place** (app, High). `goto <line>` is sent only if the last status says the machine is held. Status lags by about a second, so if it isn't yet, the `goto` is skipped and the job continues from wherever it paused, with no error shown. `lastUploadedRemotePath` only means "something was uploaded once"; nothing checks it is the program on screen. When the machine is running a generated resume file, the original-program line passed to `goto` needs the line offset subtracted (*suspected*, callers not read). *Fix:* make resume return a result, confirm Pause state and the program fingerprint first, apply the offset, and abort with a message if `goto` can't be sent. Related: the bit-change sheet skips the program-mismatch check after a resume of a resumed file (`BitChangeSheet.swift:417`).
5. **Sandbox entitlements are probably missing the bookmark entitlement** (app, High, verified file contents). `Stratum-CNC.entitlements` has sandbox, user-selected read-write, and network client and server. `ProjectBookmark` makes security-scoped bookmarks, which in a sandboxed app need `com.apple.security.files.bookmarks.app-scope`. Without it, external projects can fail to open after relaunch (not run to confirm). Also decide whether `network.server` is needed (UDP discovery listener: probably yes), and make sure the final `Info.plist` has the Local Network usage description, which this archive does not include.
6. **The engine never validates parameters** (CAM, High). `SCEngine.generateToolpaths` never calls `MachiningOperation.validate(tool:)`, and nothing in the library does. Unchecked: tool diameter ≤ 0 (the offset guard `toolRadius > 0` makes it cut on the contour), stepdown ≤ 0, target depth 0, safeZ ≤ 0 or retractZ ≥ safeZ, feed or plunge ≤ 0 or NaN, ramp/helix angle outside (0, 90), stepover range for pockets, lead-in size against available space. *Fix:* one `preflight` that throws `SC.Error.invalidParameter`.
7. **G-code writers can trap or emit garbage** (CAM, Medium, partly verified). `Int(feed.rounded())` at `SCMakeraGCodeEngine.swift:378` and `:432` traps on NaN/inf, and a zero feed writes `F0`. `number()` has no `isFinite` check, so "nan" can reach the program. Tool names, comments and program names are not stripped of newlines or `;`, so they can inject lines. *Fix:* validate all waypoints, strip control characters, throw instead of emitting.
8. **`SCPostEngine` loses the tool and returns an error string as G-code** (CAM, High). The default `toolProvider` is `{ _ in .generic }` (T1, diameter 0), so tool numbers and names are lost. On failure the function returns `"(Post processing failed: …)"` as the program text, which could be sent to the machine as if valid. *Fix:* map `SC.ToolParams` to the post's tool type and make `generateGCode` throw.
9. **Offsets can silently return the unoffset geometry** (CAM, High). `offsetContour` and `exactOffsetContour` return the input segments when everything collapses (`SCEngine+Offset.swift:25, 143`). Engraving, chamfering and pocket rings use that single-result API, so an inside cut on a shape smaller than the tool runs the tool centre on the drawn line. `buildContourToolpath` handles this correctly with `geometryCollapsed`; the others should too.
10. **Importers ignore units and fail silently** (app, Medium). No `$INSUNITS` handling in the DXF importer, so an inch drawing imports at 1/25.4 of its size (*suspected*, only if the DXF library doesn't convert). SVG treats path units as mm and uses only `viewBox.height` for the flip. On import, the file is copied into the project and added to `assets` before parsing, so a parse failure leaves an orphan asset that fails silently on every later load.

## StratumLink (machine connection)

**Verified in the code**

- **The upload payload layout is a guess.** `MakeraFraming.swift:53-68` says the file-transfer payloads are a "best-effort reconstruction" because the reference `WIFIStream.py` wasn't available. The download side, by contrast, matches the reference closely. *Fix:* capture a real upload from the official controller and diff it before anyone relies on upload. Until then uploads (and therefore every real job) are the biggest unknown.
- **The uploader can hang or finish early.** In `.verifying`, any line containing "ok" completes the upload (`GCodeUploader.swift:190`), which also matches "token", "broken" and so on. In `.arming`, any non-status line starts the transfer. While active, any line containing "error", "fail", "cancel" or "not found" fails it, including unrelated lines. There is no timeout in `.transferring` or `.verifying`, so a silent machine leaves `isActive` true forever and `uploadJob` refuses new work (Stop recovers it). *Fix:* match exact expected replies, add a verify timeout, and handle `ptypeFileRetry`/`onFileTransferFrame` once the payload is known.
- **No connect timeout.** `MachineConnection.connect` ignores the `.waiting` state (`default: break`), so an unreachable IP sits connecting with no message.
- **Protocol detection is tight.** Three probes at 0.15 s each. On a slow Wi-Fi link a plain-text machine that answers after 150 ms gets classified as framed, and every command is then ignored with no error.
- **Realtime commands silently fail before detection finishes.** `sendRealtime` returns `false` when no protocol is known yet, so a soft reset in the first half-second does nothing; `softReset()` has already stopped the runner and posted `.motionAborting`.
- **Job runner has no ack timeout.** If one "ok" is lost, the queue stalls forever. A line-level watchdog would help, at least for probe and origin sequences.
- **Pre-run steps are not acknowledged** (`startRun` with neither Auto Z nor Auto Level): the origin lines and `play` are sent back to back through `sendRawCommand`, so a rejected origin line doesn't stop the job.
- **The job overwrites G54 XY** with `originOffset` taken as machine coordinates (the doc comment admits this is unconfirmed). Any work offset the user set on the machine is lost, and if the canvas origin isn't the machine origin, the job lands in the wrong place.
- **Auto Z probes only 10 mm down from wherever the tool is**, at the current XY rather than the job origin, and zeroes Z at the trigger point (no probe-plate thickness). The doc comment says as much; surface it in the UI.
- **Connection-lost alert misses clean closes.** It fires only if `lastError != nil`, so a graceful socket close (machine powered off, Wi-Fi drop without a reset) during a job raises no alert.
- **Discovery:** the Mock Machine is always in the list (fine for development, hide in release), discovered machines are never aged out, and a machine name containing a comma breaks parsing.
- **Downloads:** a missing advertised MD5 is silently accepted, and any line with "not found" fails an active download. QuickLZ-compressed files are detected but not supported.
- **Alert rules:** tool-change detection is a keyword heuristic and the code says so. Capture the real M6 text and make it exact.
- **`CNCCommand+Builder.swift:113` uses `fatalError`** for an invalid M497 status; use a throwing or clamped path.
- Minor: `rawLog` is `@Published` and republishes on every line; `send()` appends without trimming (trimmed on the next inbound line).

## Stratum CNC (app)

**Machine control**

- **No soft-limit or work-envelope check anywhere** (grep finds none outside render layout). Job origin and jog distances are not checked against the bed, so the firmware's limits and alarm are the only protection.
- **Step jog relies on `$J` being relative** with no explicit `G91` (*suspected*, not confirmed on this firmware).
- **Game controller:** `removeController` releases buttons correctly, but stick values are never zeroed, `buttonPresses` is a single `AsyncStream` (a second consumer can steal a release; the 30 s max hold is the only backstop), and only app-level resign is handled, not a window losing key status. The `didResignActive` observer is never removed.
- **Resume preamble** does not track tool length offset (G43/G49), cutter compensation (G41/G42), G10, G93 or canned-cycle state (canned cycles only warn). `travelZ` is the program's highest Z in work coordinates, so re-probing Z after a bit change can leave it below the material (`reprobeZ` exists but is off by default). Back-up distance measured along chords underestimates arcs. `Int(word.value)` in `GCodeModalState.swift:79, 133` traps on a huge numeric word.
- **Alarm during a job** is recorded and then all further status is ignored in `JobProgress.observe`.
- Each `ProjectModel` creates its own `ControllerModel` and session, so closing a project or going back to the splash page tears down the machine connection, which matters mid-job.

**Data and persistence**

- `ProjectModel.saveIfNeeded` is `try? save()`, so a failed save (disk, revoked bookmark) is never reported.
- Metadata and toolpaths are two separate atomic writes; a crash between them leaves them inconsistent.
- `openZombieProject` starts security-scoped access and never stops it.
- `JobProgressStore` and `lastUploadedRemotePath` are one global record shared by all projects and machines.
- Autosave exists (30 s, on close, on terminate) but there is no error UI, no versioned backup and no crash recovery.

**Importers**

- DXF: splines, INSERT/blocks and HATCH are not handled and are dropped without notice (*suspected* from the entity enum); TEXT is a stub. Ellipses use at least 32 segments per turn regardless of size, and an ellipse arc with `endParam < startParam` sweeps the wrong way. A DXF arc with start equal to end gives zero sweep. Extrusion/OCS is ignored, so arcs with extrusion Z = −1 are mirrored.
- Gerber: no aperture macros (`AM`), step-and-repeat (`SR`) or aperture transforms (`LM`/`LR`/`LS`); non-UTF-8 files are skipped silently; archive entries are written without a size cap (zip-bomb risk; path traversal is correctly blocked). `GerberImporter.parse(url:)` calls `fatalError`, so any caller through the `Importer` protocol would crash.
- Several TODOs ask whether stepover is a percentage of radius or diameter (`SC.Pockets+FormFields.swift:31`, `SC.EntryStrategy+FormFields.swift:58`, `OperationOptionsView.swift:698`). If the label and the engine disagree, stepover is off by 2×. Settle it with a test.

**Performance and robustness**

- Importers and `loadAndParseFileAt` run on the main actor; a big DXF or Gerber zip freezes the UI.
- `NCFileDocument.rebuildToolpath` re-parses the whole file on each line edit (the author's own TODO).
- `GCodeStore:330` polls every 40 ms with `try?` on `sleep`, which swallows cancellation.
- G-code is read as UTF-8 only, and `\r\n` handling may not match the firmware's line numbering, which matters for line-based resume (*suspected*).
- Metal pipeline creation uses `try?`, so a shader failure gives a blank canvas with no message; `commandQueue` is an implicitly unwrapped optional.
- Errors mostly go to `print`; there is no user-visible error surface for load, save or import failures.

## StratumCAM (toolpath engine)

**Likely wrong output**

- **Chamfer offset** (`SCEngine+Chamfering.swift:46-50`, *suspected*). The centre is offset by `|z|·tan(half-angle)`, which puts the cone's top edge exactly on the drawn edge. If the drawn edge is meant to be the top of the bevel, an outside chamfer cuts nothing; a nil `vAngle` gives reach 0. Nothing checks that the bevel fits the cutter or flute length.
- **Allowance + narrow feature** (`SCEngine+Allowance.swift:224-229`). The roughing tool is `diameter + 2·allowance`; if that collapses, the function returns nil before the finishing pass, so a feature the real tool could cut is never machined (for example a 4 mm slot, 3 mm tool, 0.5 mm allowance).
- **Pocket rings silently stop at 500** (`SCEngine+Pocketing.swift:619`). A 1 mm tool at 10 % stepover on a 100 mm pocket needs about 500 rings, so larger pockets leave the centre uncut with no warning.
- **Boring** uses `targetDiameter/2` for the path radius with a flat end mill, so the bore comes out `targetDiameter + tool.diameter` wide unless the tool is meant to be a zero-diameter bar (*suspected*), and plunges to full depth with no stepdown.
- **Drilling:** after each peck the tool re-plunges at plunge feed from the retract height instead of rapiding to just above the last peck; no chip-break option; the dwell code is commented out; the hole centre is the bounding-box centre of any closed shape, which can lie outside an L-shaped outline.
- **Thread milling** places the thread at the bounding-box centre and doesn't check flute length.
- **Climb/conventional ignores spindle direction.** The mapping is correct for M3 (checked), but `ToolParams.clockwise = false` (M4) inverts it and the engine never reads it.
- **Entry at Z0** rapids to exactly the stock top (`SCEngine+Contour.swift:57, 95, 331, 411`) with no clearance, and `SC.Stock` is never read, so nothing checks depth against thickness.
- **Holding tabs** lose width at the loop seam (clipped to `[0, totalLength]`), use a fixed 0.5 mm ramp buffer (a 1.5 mm tab climbs at about 70°), and a tab taller than the depth cuts nothing.
- **Open contours with inside/outside** pick the side from the signed area of an open polyline, which is meaningless, so the side depends on drawing direction.
- **`EntityChainer`** only extends the tail of a chain, so out-of-order input produces a wrong open chain plus a stray segment; it keeps extending after closing, is O(n²), and uses a fixed 1e-3 tolerance regardless of units.
- **`calculateZPasses`** returns one full-depth pass when stepdown ≤ 0 and has no cap, so a 1e-4 stepdown on 20 mm makes 200k passes.
- **Ellipse and arc conversion:** ellipses use at least 32 samples per turn (about 0.24 mm chord error on a 100 mm ellipse); a reversed full circle starts at (−r, 0); a trimmed full circle can collapse to zero sweep.

**G-code engines**

- Two writers exist: the simple `SCGCodeEngine` (ignores `settings`, emits M3 once, no M6/coolant/G54/G40/G49/G80 resets) and `SCMakeraGCodeEngine` (also ignores `settings:`). Sections are matched by tool number only, so two tools with the same number but different diameters merge.
- `PolygonOffset.swift:807`: timing logs print to the console by default through a mutable global (`OffsetTiming.isEnabled`).
- `SCPostEngine` runs the `.cps` in JavaScriptCore with no timeout and `Carvera.cps` is not in the archive.
- Everything is mm: `G21` hard-coded, absolute epsilons, `ToolParams.diameter` annotated "(mm/in)".
- Dead code: unused `SC.Stock`, the commented-out dwell block, unused `settings:` parameters. TODO/FIXME markers at `SC+ClearingPattern.swift:145`, `SC+Contour.swift:25`, `SCEngine.swift:188, 195`, `+Slotting.swift:611`, `+Pocketing.swift:406`, `+Contour.swift:1013`.
- Not read in depth: Pocketing, PocketAdaptive, PocketIslands, PocketBoundary, PocketCenter, RestMachining, RestCorners, Slotting, Counterbore, PolygonOffset and the rest of ThreadMilling; only greps and skims there. Those are the most complex files, and they are the ones most worth a dedicated geometry test suite.

## What is missing

**Quality**

- **Tests.** None. Easy wins because the logic is pure: resume/modal-state scanning, `GCodeBounds`, frame encode/parse and CRC, `calculateZPasses`, offsets (golden contours), bulge arcs, unit conversions, and a golden-file comparison of `SCMakeraGCodeEngine` against `SCPostEngine`. A `MockMachineSimulator` already exists, which makes session-level tests feasible.
- **Undo/redo** (no `UndoManager` use). Deleting an object or toolpath is permanent apart from autosave.
- **User-visible errors** for load, save, import and generation failures, and engine **warnings** (the `Warning` enum has two cases) for skipped or truncated geometry.

**CAM features** (compared with a typical 2.5D CAM)

- V-carve and area engraving (`.engrave` is centre-line only).
- Chip-break drilling (G73), drill-tip compensation, spot drilling and tapping.
- Tool-change ordering, hole and toolpath ordering for shorter rapids, duplicate tool-number checks.
- Stock-aware rapids, stock bounds, a true rest-machining stock model, bottom-clearance past the stock.
- Tab shapes, automatic tab placement, G41/G42 output as an option.
- Coolant and air-blast output (Carvera supports it), G53 safe retract before tool change, multiple work offsets.
- Simulation with collision checks against stock, fixtures and holder (a heightmap preview exists, but nothing flags a rapid through material).
- Inch/mm display switching, STEP import (the folder is empty), DXF splines and blocks.

## Positives

- **Resume design** is well thought out: stop and unlock, regenerate modal state from the program, raise Z before XY, handle units and G90/G91, map line offsets back to the original, refuse when position is unknown, and bound the back-up by the pass start.
- **Session layer:** run options captured at start so later edits can't change a running job; leveling refuses to run unleveled when requested; pending `play` is cleared on disconnect, Stop and Alarm and guarded by a run UUID; alerts de-duplicate against both text lines and status changes.
- **Jog** has real safety work: `.common` run-loop mode, elapsed-time travel with a catch-up cap, a 30 s max hold, stop on Alarm or `motionAborting`, stop on app resign.
- **Framing code** is clean: CRC table, length bounds, resync on bad footer, fragment reassembly for text frames. The downloader follows the reference closely, with retries, MD5 check and cancel handling.
- **CAM:** Sendable value types, self-describing `OperationRequirements` for the UI, specific `SC.Error` cases; `calculateZPasses` derives depth by multiplication so there is no drift; exact offset with a validated polygon fallback; careful arc handling (full circles split, seam-safe angle tests, bulge arcs); locale-independent number formatting; `SCPostEngine` validates JSON for NaN/inf.
- **App:** atomic writes, debounced autosave with flush on terminate, ref-counted bookmark access with stale refresh, path-traversal-safe ZIP import, stale-result protection and cancellation for heightmap and toolpath tasks, on-demand Metal drawing.

## Suggested order of work

1. Persistence safety (item 1) and the bookmark entitlement (item 5): small changes, prevent data loss.
2. Stop-after-play and jog-cancel (items 2 and 3): small changes, safety critical.
3. Capture a real upload and a real M6 prompt from the official controller, then make the uploader and alert matching exact.
4. Engine preflight validation plus finite-number checks in the writers (items 6, 7, 8, 9).
5. Start a test target with the pure-logic pieces listed above, then fill in the geometry-heavy files that this review only skimmed.

## Coverage

- **Read in full or in depth:** all of StratumLink; StratumCAM models, SCEngine, Contour, Offset, Allowance, EntryHeight, RetractPolicy, RampTools, Drilling, Boring, Chamfering, Facing, both G-code writers, SCPostEngine; app `JobCoordinator`, `GCodeModalState`, resume preamble and resolver, `BitChangeFlow`, `GameControllerStore`, jog, `ProjectModel`, `ProjectsStore`, `ProjectBookmark`, entitlements, `DXFImporter`, the `CAMModel` import path, the Gerber parser.
- **Skimmed or grepped only:** the StratumCAM pocketing/slotting/offset-polygon files listed above; in the app the SVG importer, Gerber arcs and apertures, `ToolpathGenerator`, `MetalRenderer`, `CanvasSceneModel`, tools and stocks stores, `NCFileDocument`, `BitChangeSheet`.
- **Not opened:** `MachiningRunSheet`, `ControllerView`, macros, probe/coordinate panels, Excellon parser, 3D view.
