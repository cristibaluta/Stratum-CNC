# Pause / Suspend / Resume: Plan

## Goal
Pause a running job and resume it later (long job, broken bit, heat, app restart), with the logic **owned by the app**, not by StratumLink.

## Principle
StratumLink stays a thin transport: connect, send a line, receive a response, report status.
It should not decide what a pause, suspend or resume means. The app decides:
- what to send (retract, `M5`, preamble, plunge)
- which line to restart from
- what to persist

## Current state
- `ControllerModel` delegates `pauseJob`, `suspendJob`, `resumeJob` and `resumeJob(fromLine:)` to `SL.Session`.
- Suspend and "goto line" rely on machine/firmware console commands (`suspend`, `goto N`) driven by StratumLink.
- `GCodeViewer` shows the pause, suspend, resume and "Resume from Line N" buttons.
- Only `lastUploadedRemotePath` is persisted (UserDefaults). There is no job progress record.
- Parsing and analysis already exist in the app: `GCodeParser`, `GCodeToolpathAnalyzer` (toolpaths with `startLine`/`endLine`/`toolNumber`) and `NCFileDocument`.

## Step 0 result: StratumLink audit (done)

Source: `/Users/cristianbal/Documents/StratumLink/Sources/StratumLink` (local package, `../StratumLink`).
Target machine: **Makera Carvera** (Smoothieware-based). Two wire protocols: `.makera` (framed binary) and `.smoothie` (plain text).

### Key finding: the firmware runs the job, not the app
A whole program is uploaded to the SD card (`GCodeUploader`) and started with the console command `play <path>`.
The firmware then streams, plans and tracks the line on its own. `GCodeJobRunner` (ack-by-ack streaming) is documented as unsuitable for a whole job on real Makera hardware: it is only for small bursts (macros, probing).
So the app **cannot** own line streaming for real jobs. It can own the **policy**: what to send and when, which file to run, and what to persist.

### Inventory

| Item | Location | Class |
|---|---|---|
| `MachineConnection.send`, `sendRealtime`, `sendRawBytes`, `sendFileFrame`, `requestStatus`, `onLine`, `$status` | `Makera/MachineConnection.swift` | **Transport**: stays |
| `MakeraMachineStatus` (`isRunning`, `isFeedHeld`, `isSuspended`, `activeJob`, `lastJob`) and `MakeraPlayback.currentLine` (1-based file line) | `Makera/MachineConnection.swift:30-170` | **Transport/status parsing**: stays |
| `MachineSession.sendRawCommand` + realtime routing (`?` `!` `~` `^X`) | `Session/MachineSession.swift:277` | Transport: stays |
| `GCodeUploader.upload`, `cancel`, `onCompleted` | `GCode/GCodeUploader.swift` | Transport (file transfer): stays |
| `GCodeJobRunner` (queue, `awaitingAck`, pause/resume/stop) | `GCode/GCodeJobRunner.swift` | Transport-ish helper for macros: stays, optional |
| `pauseJob()` (feed hold if `status.isRunning`) | `MachineSession.swift:476` | **Policy**: move to app |
| `suspendJob()` (guards, sends `suspend`, records `suspendRequestedAt`) | `MachineSession.swift:496` | **Policy**: move to app |
| `resumeJob()` / `resumeJob(fromLine:)` (`goto N`, then `resume` or `~` depending on status) | `MachineSession.swift:509-541` | **Policy**: move to app |
| `stopJob()` (cancel upload or soft reset; clears `pendingPlayPath`) | `MachineSession.swift:548` | **Policy**: move to app |
| `lastUploadedRemotePath` + `onLastUploadedRemotePathChange` | `MachineSession.swift:94-97` | **Policy/state**: move to app (`JobProgress`) |
| `startRun`, `levelingFinished`, `playWhenIdle`, `applyJobOrigin` (origin → Z probe → G32 level → wait Idle → `play`) | `MachineSession.swift:370-466` | **Policy**: move to app (run orchestration) |
| `MachineRunOptions`, `uploadJob(fileName:contents:options:)` | `MachineSession.swift:13, 333` | Policy: move to app |
| `autoZeroProbe()` | `MachineSession.swift:592` | Policy: move to app |
| `machineStateChanged` + `MachineAlert` / `MachineAlertRules` (suspended job on connect, paused by machine, alarm) | `MachineSession.swift:624`, `Session/MachineAlert.swift` | Policy/UX: move to app (keep raw line/state events in the library) |
| `jobOriginCommands`, `zeroCommand`, `homeCommand`, `unlockCommand`, etc. | `MachineSession.swift:101-126, 306-326` | Command builders: can stay as `CNC` helpers, or move |

### What the app calls today
`ControllerModel` wraps `SL.Session`: `pauseJob`, `suspendJob`, `resumeJob`, `resumeJob(fromLine:)`, `stopJob`, `startJob(lines:)`, `uploadJob`, `cancelUpload`, `autoZeroProbe`, `jobOriginCommands`, `sendRawCommand`, plus the command constants. Wiring: `ControllerView.swift:425-430` → `GCodeViewer.swift:290-333`. The app also reads `connection.status.activeJob.currentLine` for progress and `lastUploadedRemotePath` for `canResumeFromLine`.

### Machine commands the policy relies on
- `!` feed hold and `~` cycle resume (realtime), `^X` soft reset.
- `suspend` / `resume` console commands: the firmware saves the position, stops the spindle, and keeps the suspended state across app restarts.
- `goto <line>`: **documented by Makera** (https://wiki.makera.com/en/supported-codes, Console Commands). "Resume a job from a certain line": the job must be running and then **paused**; while paused, `goto <line>` makes it jump to that line, then resume continues. The docs warn to be careful with Z height and to lift Z a bit after pausing. So `goto` only works on a job that is loaded and paused; it does not work on an idle machine.
- `play <path>`: start a file from the SD card.
- Status states: `Run`, `Hold`, `Pause` (= suspended), `Idle`, `Alarm`.

### Consequences for the plan
1. Step 1 changes. Instead of an app-side line streamer, build an app-side **`JobCoordinator`** that owns the job state machine and policy, and drives the library only through transport calls (`send`, realtime, upload, status). Line streaming stays on the firmware.
2. `goto <line>` is the primary resume-from-line mechanism, because the firmware supports it. Precondition: the job is loaded and paused (feed hold or `suspend`). Sequence: pause/suspend → lift Z → preamble lines → `goto N` → resume. When the job is **not** loaded (after a power cycle, soft reset, alarm, or a finished or stopped job), `goto` is not available. The app then falls back to a **generated resume file** (preamble + lines from the safe restart point), uploaded and started with `play`. Steps 4 and 5 apply to both paths.
3. `suspend` / `resume` on the machine already survive an app restart, so `JobProgress` persistence matters most for: resuming after a hard stop, a power cycle, an alarm or a soft reset (where the firmware state is gone), and for validating that the file on the machine matches the project.
4. Firmware `currentLine` is a physical file line. Keep it as the source of the "last known line" in `JobProgress`.
5. Test on the real Carvera: `goto` with `suspend` vs feed hold, and resume after a soft reset.

## Steps

### 0. Audit StratumLink (discovery): DONE
- [x] Listed everything in `SL.Session` / `SL.JobRunner` related to pause, suspend, resume, resume-from-line, goto, and job progress (see "Step 0 result").
- [x] Classified each item as stay (transport) or move to app (policy).
- [x] Minimal transport API the app needs: `send(line)`, `sendRealtime`, `requestStatus` + `$status` (state, `activeJob.currentLine`), `onLine`, `uploader.upload`/`cancel`/`onCompleted`.
- [x] `goto <line>` confirmed in the Makera docs (requires a paused job).
- [ ] Open: test on the real Carvera how `goto` behaves with `suspend` vs feed hold (`!`), whether modal state (spindle, feed, units) is restored after the jump, and what happens after a soft reset.

### 1. App-side job coordinator
- [ ] Create `JobCoordinator` (app layer, e.g. `controller/job/`) that owns the job state machine (`idle / uploading / preparing / running / held / suspended / stopped / failed`, derived from `connection.status` plus local state) and the policy for pause, suspend, resume and stop.
- [ ] Move into it from `MachineSession`: `pauseJob`, `suspendJob`, `resumeJob(fromLine:)`, `stopJob`, run orchestration (`startRun`, `playWhenIdle`, `applyJobOrigin`), `autoZeroProbe`, `MachineRunOptions`.
- [ ] It drives the machine only through the transport API. The firmware still streams the file (`play <path>`); do not stream whole jobs line by line.
- [ ] `ControllerModel` calls `JobCoordinator` instead of `session.pauseJob()` and the rest.
- [ ] Keep `GCodeViewer` callbacks unchanged so the UI doesn't need to change.
- [ ] Deliverable: run, pause (feed hold) and resume work through the app.

### 2. Persist job progress (`JobProgress`)
- [ ] Add a `Codable` `JobProgress` to the project data:
  - file fingerprint (SHA256, already computed in `sendJob`)
  - last acked line
  - state
  - active WCS (G54–G59)
  - tool number
  - stock reference
  - timestamp
- [ ] Write it on every state change and every N acked lines (throttled).
- [ ] Clear it on completion or an explicit stop.
- [ ] On launch or project open, detect an unfinished `JobProgress` and offer **Resume**.
- [ ] Validate the fingerprint. If the file changed, refuse to resume or warn.

### 3. Safe suspend (app-owned)
- [ ] Sequence: feed hold → wait for Hold state → `G53 G0 Z<safe>` → `M5` → coolant off → optional park → record `JobProgress`.
- [ ] Safe Z and park position come from machine settings.
- [ ] Triggers: the user pressing Suspend, and later thresholds (heat or alarm).

### 4. Resume preamble
- [ ] `GCodeModalState.at(line:)` scans the file from the start to line N and collects units, G90/G91, plane, feed mode, tool, spindle speed and direction, coolant, last F.
- [ ] Job still loaded and paused: lift Z, send the preamble lines (modal state, spindle on and wait, tool), `goto N`, then resume.
- [ ] No job loaded: **generate a resume file** (preamble + lines from the restart point), upload it and `play` it.
- [ ] `ResumePreambleBuilder` emits: modal state → tool and offset → `M3 S…` → `G4 P…` spin-up wait → safe Z → rapid XY → slow plunge to Z → continue at line N.
- [ ] Unit tests (`Stratum CNC Tests/`): modal state at line N, and preamble for the line after a tool change, mid-arc and in relative mode.

### 5. Safe restart points
- [ ] `ResumePointResolver` snaps the requested line to the start of the enclosing toolpath/pass using `GCodeToolpathAnalyzer` (`startLine`).
- [ ] Never start mid-arc. Optionally allow "exact line" as an advanced choice.
- [ ] Show the resolved line in the "Resume from Line" button and help text.
- [ ] Unit tests.

### 6. Bit change / broken bit flow
- [ ] A guided sheet: retract and stop → "Replace the bit" → choose same or different tool.
- [ ] Re-probe Z (or tool length), and apply the delta as the tool offset.
- [ ] Offer "restart current pass" (default) or "back up N mm".

### 7. Verify before resuming
- [ ] Resume review sheet: resume line, canvas preview of the completed portion, WCS and position check.
- [ ] Optional "air cut first": run to the resume point with Z raised, then confirm.

### 8. Remove the old path
- [ ] Remove the pause, suspend, resume, stop and run-orchestration code and `MachineAlert` policy from StratumLink `MachineSession` (keep transport, status parsing, uploader), and drop `lastUploadedRemotePath` as the resume mechanism.
- [ ] Update `README.md` / docs.

## Rules and pitfalls
- Don't trust the machine position after an alarm or soft reset. Re-home first.
- Use stored WCS (G54–G59), never a temporary G92.
- Always include spindle spin-up delay and coolant state in the preamble.
- Plunge slowly at the resume point.

## Order of work
0 → 1 → 2 → 5 → 4 → 3 → 7 → 6 → 8
(1 and 2 first for persistence, 5 and 4 for correct restarts, the rest builds on them.)
