# 3D Probing: Implementation Plan (Stratum CNC)

Goal: a dialog in the controller that guides the user through finding the **Z surface, a corner, or the center** of the stock with the 3D probe, then sets the work origin from the result.

This plan is based on the code in the zip (`controller/`, `stocks-lib/`, `metal-canvas/MachineLayout.swift`, `controller/Coordinates.md`). The `StratumLink` package was **not** in the zip, so anything that depends on it is listed under [Open questions](#13-open-questions-to-check-first).

---

## 1. What exists today

| Piece | Where | Notes |
|---|---|---|
| Probe row: `Z`, `X`, `Y`, `Auto Z` | `controller/panels/PanelProbe.swift` | Sends `CNC.probe.with(z: -10, feed: 50)` etc. Fixed distance, no ball compensation, no result handling. |
| Auto Z | `JobCoordinator.autoZeroProbe()` | Sends probe + `zeroCommand(z:)` through `jobRunner`, which advances on each line's `ok`. |
| Dialog pattern | `BitChangeSheet` + `BitChangeFlow` + `model.isShowingBitChange` + `.sheet` in `ControllerView` | Pure flow struct, a sheet that presents it. **Reuse this exact pattern.** |
| Jogging | `JogController`, `PanelJog`, `model.jog(...)`, game controller | Works on the model, not tied to a view. |
| Stock | `StockMaterial.geometry`: `.rectangular(width,height,depth)`, `.cylindrical`, `.disk(outer, inner, depth)` | Gives us the drawing and the expected size. |
| Machine layout | `MachineLayout`: anchors, `workOrigin(xyOffset:)`, `scene.xyOffset` | The probed origin must stay consistent with this (see 7.3). |
| Persisted settings | `levelBeforeRun`, `levelGridPoints`... in `ControllerModel` via `UserDefaults` | Same style for probe settings. |
| Probe response parsing | not found in the zip | Probably inside `StratumLink`. |

---

## 2. User flow (4 steps)

```
 [1 What]  →  [2 Position]  →  [3 Probe]  →  [4 Result]
```

### Step 1: What do you want to probe?

- **Probe type** (big selectable tiles):
  - Z surface
  - Edge X / Edge Y (optional, cheap to add)
  - Corner (XYZ)
  - Center
- **Shape** segmented control: `Rectangle | Circle`
  - Default comes from the stock: `.rectangular` → Rectangle; `.cylindrical` / `.disk` → Circle.
  - Rectangle: Z, Edge, Corner, Center all available.
  - Circle: Center only (plus Z). When Circle is selected, a second small control appears: `Outside (boss) | Inside (hole)`. A `.disk` with an inner diameter defaults to Inside.
- A one line explanation under the selection ("Corner: touches the top, one side in X and one side in Y, then sets X0 Y0 Z0 at that corner").

### Step 2: Position the probe (the key screen)

Left: **stock drawing**. Right: **instructions + jog + live position**.

- Top view of the stock drawn to scale from `StockGeometry` (rectangle or circle/ring), with width/height labels and X/Y axis arrows.
- **Corner mode:** the 4 corners are clickable handles on the drawing; the selected corner is highlighted.
- **Pulsing dot** = the **target jog position** (where the probe tip should be above), *not* where the probe is now. A label under the drawing says so ("Jog the probe tip above the dot").
- Instruction text that changes with the choice, for example:
  1. Load the probe (T0) if it is not in the spindle.
  2. Jog the tip above the pulsing dot, about 5–10 mm above the stock.
  3. Z does not need to be exact; XY should be within ±2 mm of the dot.
- Live readout of WCS/MCS from `connection.status`, so the user can see the jog happening.
- An embedded jog (reuse `PanelJog`, see 7.1) because a sheet is modal.
- `Continue` is enabled only when the machine is connected, idle, and the checklist is done.

Where the dot goes (stock local coordinates, W = width, H = height, `i` = start inset):

| Mode | Dot position |
|---|---|
| Corner bottom-left | `(i, i)` |
| Corner bottom-right | `(W − i, i)` |
| Corner top-left | `(i, H − i)` |
| Corner top-right | `(W − i, H − i)` |
| Center (rectangle) | `(W/2, H/2)` |
| Center (circle, outside or inside) | circle center |
| Z surface | stock center, or the same spot as the chosen corner |

`i` defaults to 10 mm and is clamped to `min(10, W/4, H/4)` so small stock still works.

### Step 3: Probe

- Summary of what will happen (a list of moves, with the safe height and feeds).
- **Safety checklist**, all must be ticked:
  - Probe is in the spindle and wired/awake (touch it by hand: the app shows "triggered")
  - Spindle is off
  - Probe tip is above the dot and above the stock
  - Nothing clamped above the stock that the probe could hit
- Buttons: `Start`, `Stop` (feed hold, then soft reset like `JobCoordinator` does).
- Progress list: each move gets a checkmark as it completes; the current one has a spinner.
- Failure ("no contact", alarm, lost connection) stops the sequence, shows the reason, and offers `Retry` / `Back`.

### Step 4: Result

- Table of measured values: edge positions, stock size (measured vs stock library), the new origin in machine coordinates.
- **Warning** if measured size differs from the stock by more than a tolerance (default 1 mm): wrong stock selected, or a wrong edge was touched.
- `Apply`: sets the work origin (G54) and updates the canvas offset (see 7.3). `Discard` leaves the origin unchanged.
- Optional `Go to origin` (safe Z, then XY).

---

## 3. Settings

Persisted with `UserDefaults` (a `Codable` `ProbeSettings` struct, same idea as `levelBeforeRun`). Shown in a collapsible "Settings" section in Step 2 and Step 3, and also in the app `SettingsView`.

| Setting | Default | Purpose |
|---|---|---|
| **Safe Z** (clearance above stock top) | 10 mm | Height used for every travel move between probes. |
| **Safe position** (optional XY park position) | off | Where the probe goes after finishing (machine coordinates, or "stay at origin"). |
| **Search feed** | 100 mm/min | First, fast touch. |
| **Measure feed** | 10–20 mm/min | Second, slow, accurate touch. |
| **Retract distance** | 1.5 mm | Back-off between the two touches. |
| **Search distance (max travel)** | 20 mm | Longest probe move. Stops runaway moves. |
| **Probe ball diameter** | 2 mm (make it required, no silent default if unknown) | Compensation for X/Y. |
| **Z offset / reference** | 0 | Probe tip vs. tool tip, if the machine does not already apply it. |
| **Edge probe depth** | 3 mm below top, never more than stock depth − 1 mm | How deep the probe goes before touching a side. |
| **Outside clearance** | 5 mm | How far past the expected edge the probe starts a side touch. |
| **Start inset `i`** | 10 mm | Distance of the pulsing dot from the corner. |
| **Probe tool number** | T0 | Carvera's wireless probe. |
| **Work coordinate system** | G54 | Where the result is written. |
| **Set Z as well** | on | Corner/center can leave Z untouched. |
| **Two-pass touch** | on | Fast then slow. Turning it off is faster but less accurate. |

---

## 4. Probing math

Notation: `r` = ball radius, `d` = direction of the probing move on that axis (+1 or −1), the work frame has X to the right and Y up in the drawing.

- **Edge:** the machine stops when the ball touches, so the ball center is `r` before the edge.
  Edge coordinate = contact + `d·r`.
  To make that edge zero: `G10 L20 P1 X<−d·r>` (same for Y).
  - Left edge, moving +X: `L20 X-r`
  - Right edge, moving −X: `L20 X+r`
  - Bottom edge, moving +Y: `L20 Y-r`
  - Top edge, moving −Y: `L20 Y+r`
- **Z top:** probe down, set `G10 L20 P1 Z<zOffset>`.
- **Rectangle center:** two touches per axis, from outside on each side.
  `center = (c1 + c2) / 2` (the radius cancels out).
  `width = |c2 − c1| − 2r` (outside probing).
- **Circle boss (outside):** touches at `±X`, `±Y` from outside.
  `center = midpoints`, `diameter = distance − 2r`.
- **Circle hole (inside):** touches at `±X`, `±Y` from inside.
  `center = midpoints`, `diameter = distance + 2r`.
- **Refine:** for circles, probe once roughly, move to the computed center, probe again.
- **Stock check:** compare measured size to `StockGeometry`.

Note: for edges that only need a zero, `G10 L20` right after the touch needs **no result parsing** (the tool is exactly at the contact point). Center and circle need the measured values, so they do need the result.

---

## 5. G-code sequence (corner example, bottom-left)

Illustrative; use the real builders (`CNC.probe`, `CNC.rapidMove`).

```
G92.1                         ; clear stale G92 shift (see Coordinates.md)
G54
G91                           ; relative moves from here

; --- Z top ---
G38.2 Z-20 F100               ; fast touch
G0 Z1.5
G38.2 Z-3 F15                 ; slow touch
G10 L20 P1 Z<zOffset>
G0 Z<safeZ>

; --- X edge (left side) ---
G0 X-<i + clearance>          ; move outside, at safe Z
G38.2 Z-<edgeDepth + safeZ> F50   ; lower with a probe move (see 9: crash guard)
G38.2 X<searchDistance> F100  ; fast touch toward +X
G0 X-1.5
G38.2 X3 F15                  ; slow touch
G10 L20 P1 X-<r>
G0 X-<retract>
G0 Z<safeZ>                   ; back up, ready to come back

; --- Y edge (bottom side), same pattern ---

G90
G0 Z<safeZ>                   ; finish
```

The exact commands and the response format on the Carvera must be confirmed (see section 13).

---

## 6. Architecture and files

New folder: `controller/probing/`.

| File | Responsibility |
|---|---|
| `ProbeSettings.swift` | Codable settings + `UserDefaults` persistence. |
| `ProbeCycle.swift` | Enums: `ProbeKind` (z, edge, corner, center), `ProbeShape` (rectangle, circle), `Corner`, `CircleSide`. |
| `ProbeFlow.swift` | **Pure** state: current step, selection, checklist, validation, where the dot goes. Same style as `BitChangeFlow`. |
| `ProbeCycleBuilder.swift` | **Pure**: turns selection + settings + stock into an ordered list of `ProbeAction` (move, probe, retract, compute, set origin). |
| `ProbeSequencer.swift` | Runs the actions against the machine, one at a time, and collects results. |
| `ProbeResult.swift` | Measured values, computed origin, stock comparison. |
| `ProbeSheet.swift` | The dialog (steps 1–4). |
| `ProbeStockDiagram.swift` | The drawing, corner handles, pulsing dot. |
| `ProbeSettingsView.swift` | The settings form (used in the dialog and `SettingsView`). |

Changes to existing files:

| File | Change |
|---|---|
| `ControllerModel.swift` | `@Published var isShowingProbe`, `probeSettings`, a method that starts a sequence, a method that applies a result. |
| `ControllerView.swift` | `.sheet(isPresented: $model.isShowingProbe) { ProbeSheet(...) }`, next to the existing sheets. |
| `PanelProbe.swift` | New button "3D Probe…" that opens the dialog. Keep the `Z`/`X`/`Y`/`Auto Z` quick buttons. |
| `PaletteCommand` / `favoriteCommands` | Optional: "Open 3D probing". |
| `CanvasSceneModel` | Receive the new `xyOffset` after applying a result (see 7.3). |

### Why a sequencer and not only `jobRunner.start(lines:)`

`jobRunner` sends fixed lines and advances on `ok`. That is enough for "probe, then zero", but center and circle cycles need a **measured value to build the next move**. The sequencer sends one segment, waits for its `ok`, reads the result, then builds the next segment. If the result cannot be read from the response, use the fallback in 13.1.

---

## 7. Important things to handle (extra info)

### 7.1 The dialog is modal, but the user must jog

A SwiftUI `.sheet` blocks the main window, including `PanelJog`. Options:

1. **Embed a jog pad in the dialog** (recommended): reuse `PanelJog(model:joystick:holdFeed:)`. The game controller already works because `JogController` lives on the model.
2. Make the dialog non-modal (a floating panel or an inspector), so the real panels stay usable.

### 7.2 Run conditions

Disable `Start` unless: connected, state is `Idle` (not `Alarm`, `Run`, `Hold`), no job running (`jobRunner.isActive`, `job` coordinator), and the probe tool is in the spindle.

### 7.3 Probed origin vs. canvas offset (very likely to bite)

`Coordinates.md` says the typed canvas offset and touch-off end up as the same stored work offset and *the last one wins*. When a job starts, `JobCoordinator.startRun` sends `SL.Session.jobOriginCommands(for: offset)` (`G10 L2 ...`) which **overwrites** whatever the probe set.

So after `Apply`, update the canvas offset to match the probed origin:

```
xyOffset = probedOriginInMachineCoords − machineLayout.activeAnchor
```

(from `MachineLayout.workOrigin = activeAnchor + xyOffset`). Otherwise the job will run at the old offset and the probing result is lost.

Also: use `G10 L2` (absolute) when storing, and show the resulting machine position in the Result step.

### 7.4 Origin vs. the CAM job origin

The probed corner or center becomes X0 Y0. The G-code was posted for a specific origin (Fusion/Carvera header, top-left, stock center, etc.). If those differ, the job lands in the wrong place. In Step 4, show "Origin set at: bottom-left corner" and compare with the origin the loaded program expects, if the header says (`FusionHeaderParser`, `MakeraCAMHeaderParser`).

### 7.5 Z and tool length

Z0 set with the probe is the probe's reference. When the cutting tool is loaded, the machine applies the tool-length offset (the Carvera measures the tool on `M6`/`M491`). Confirm with the machine that Z0 stays on the stock top after the tool change, and make the Result step say which tool the Z was set with.

### 7.6 Z must be known before X/Y

Side touches happen at a depth below the stock top. So a Corner/Center cycle either probes Z first (default), or the user ticks "Z is already set". If Z is not set, only allow Z or ask for it.

Use `StockGeometry` depth to **clamp the edge depth** so the ball never goes below the stock bottom.

### 7.7 Stock geometry cases

- Rectangular: full support.
- Disk: circle, Outside (boss) or Inside (hole, uses the inner diameter).
- Cylindrical (lying on the bed): top view is a `length × diameter` rectangle. Treat as Rectangle for X/Y; Z probe should be on the centerline (Y center), because the top of a cylinder is a line. Add a hint in the dialog.
- Units: check how the app handles inch vs mm and use it everywhere.

### 7.8 Undo

Before `Apply`, store the previous G54 offset so the user can `Revert origin`.

### 7.9 Rotation check (later)

Two touches along one long edge give the stock angle (`atan2`). Show a warning above ~0.3° (no compensation in v1).

---

## 8. The stock drawing and the pulsing dot

- Draw with SwiftUI `Canvas`, scaled with `aspectRatio` to fit the available area, with padding for labels.
- Rectangle: rounded rect with W × H labels. Circle: circle (and an inner circle for a disk with a hole).
- Corner handles: four small circles at the corners (hover/click), selected one filled with the accent color.
- Probe path hint: thin arrows that show the X touch and the Y touch for the selected corner (light, so they do not compete with the dot).
- Pulsing dot:
  - A solid center dot plus an expanding, fading ring, repeating (`withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false))`).
  - Respect `accessibilityReduceMotion`: no pulse, just a ring.
  - Moves with a short animation when the corner changes.
  - Tooltip and caption: "Jog the probe tip above this point".
- Orientation: draw as seen from above, X to the right, Y up (work frame). The canvas shows machine coordinates with home at the top-right, so add a small "front of machine" marker to avoid confusion.
- Optional later: show the live probe position as a second, quiet marker. Not in v1 (the user said we do not know it; the machine status gives only the current position, and the drawing is in stock coordinates, which assumes the stock is at the anchor).

---

## 9. Safety

- Every probe move has a **max travel** and a **low feed**. No unbounded moves.
- Check the probe is **not already triggered** before starting; if it is, abort ("probe is triggered or not connected").
- **Crash guard when lowering beside an edge:** lower with a probe move (`G38.2 Z-…`), not a rapid. If it touches before reaching the depth, the start position was wrong (the tip is above the stock, not beside it): stop and tell the user.
- `G38.2` with no contact raises an error/alarm: catch it, stop the sequence, show a clear message.
- Always retract to **safe Z** before any XY travel.
- `Stop` sends a feed hold and soft reset (reuse what `JobCoordinator` does).
- Disable feed override effects if the controller supports it, and use `G21`/`G90`/`G91` explicitly, restoring `G90` at the end.
- Clear `G92` and select `G54` before starting.
- Spindle off, and refuse to start if a program is running.
- Make the user confirm the ball diameter the first time.

---

## 10. Testing

- **Unit tests** (no machine): `ProbeCycleBuilder` output for each corner, all signs of `−d·r`, center math, circle inside/outside, clamping of inset and edge depth.
- **Dry run**: a toggle that prints the generated lines to the terminal log (`connection.appendLog`) without sending.
- **Simulator**: the mock machine (`isMock`) for the UI and sequencing. It cannot test real probing results.
- **Machine tests**, in order: probe trigger by hand → Z only → single edge on a known block → corner → center → circle with a pin of known diameter. Compare the measured size with calipers.

---

## 11. Milestones

| # | Deliverable | Notes |
|---|---|---|
| 1 | `ProbeSettings`, enums, `ProbeFlow` + unit tests | No UI yet. |
| 2 | `ProbeSheet` shell (steps 1–4), `ProbeStockDiagram` with corner picker and pulsing dot, button in `PanelProbe` | Works with the simulator, no machine moves. |
| 3 | `ProbeCycleBuilder` + dry-run output | Math verified by tests. |
| 4 | `ProbeSequencer`: Z top and single edge on a real machine | First real test. |
| 5 | Corner cycle (all 4 corners) + apply origin + canvas offset sync | Section 7.3. |
| 6 | Center of rectangle | Needs result reading. |
| 7 | Circle boss/hole, refine pass | |
| 8 | Result checks (stock size warning), revert, rotation hint, polish | |

---

## 12. Out of scope for v1 (ideas)

- Tool length / tool setter probing (separate from stock probing).
- Probing a vise or fixture.
- Automatic stock rotation compensation.
- Saving probe results per project, history list.
- Probing a pocket (rectangular inside).
- Starting outside the stock (alternative to the "start over the stock" approach).

---

## 13. Open questions to check first

1. **How are probe results delivered?** The `StratumLink` package was not in the zip. Find whether it exposes the `[PRB:x,y,z:1]` message (or the Carvera equivalent) in `SL.Connection`/`SL.Session`. If not, add parsing there. **Fallback:** after each probe's `ok`, request status (`connection.requestStatus()`) and read the machine position: the machine stops at the trigger point, so that position is the contact point.
2. **Exact Carvera behavior of `G38.2`–`G38.5`** (feed limits, alarm/error output, response format). Check Makera's supported-codes page (already linked in `Coordinates.md`) and test on the machine.
3. **Is the probe state visible in the status report?** (`Pn:P` in GRBL.) Needed for the "probe triggered" check and the checklist. If it is not available, the checklist stays manual.
4. **What does `CNC.probe.with(...)` emit exactly**, and is `zeroCommand` an `L20`? (`Coordinates.md` already flags this as unconfirmed.)
5. **Wireless probe on the Carvera:** is it picked with `M6 T0`, does it need to be woken up, and what is its measured ball/tip offset?
6. **Does a stored `G10 L2` survive a power cycle?** (Also open in `Coordinates.md`.)
7. **Where should "safe position" live?** Per project, per machine, or global. This plan puts it in global probe settings.
8. **Which corner/origin does the CAM output assume?** (see 7.4)
