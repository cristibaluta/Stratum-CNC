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

### 1. App-side job coordinator: DONE (`controller/job/JobCoordinator.swift`)
- [x] Created `JobCoordinator`. Phase tracking is minimal for now (`isPreparing`); a full state enum (`uploading / running / held / suspended / ...`) comes with step 2, when progress is persisted.
- [x] Moved in: upload / upload-and-run / run-uploaded, pre-run origin, Z probe and leveling, `play` when Idle, pause, resume (with `goto`), stop, `autoZeroProbe`, `lastUploadedRemotePath` persistence, `JobRunOptions`. The coordinator takes over the session's `uploader.onCompleted` and `jobRunner.onFinish` / `onFailure` hooks, so the library's own run sequence no longer fires.
- [x] It drives the machine only through the transport API; the firmware streams the file.
- [x] `ControllerModel` calls `JobCoordinator` (`model.job`). Fixed on the way: "Send to Machine" used to start the job automatically after upload, and `startSentJob()` was a stub. Now Send only uploads, and Start runs the uploaded file.
- [x] `GCodeViewer` callbacks unchanged.
- [x] Deliverable: run, pause (feed hold) and resume work through the app. Builds; not yet tried on a machine.
- [ ] Left for later: `suspend()` still calls `session.suspendJob()` (it records that the suspend was ours, for the alert policy). Moves with the alert policy in step 8.

### 2. Persist job progress (`JobProgress`): DONE (`controller/job/JobProgress.swift`)
- [x] `JobProgress` (`Codable`): file name, fingerprint (SHA256, nil if the upload was in an earlier session), SD path, origin X/Y, total lines, last line, percent, phase (`starting / running / held / suspended / stopped / alarm / interrupted`), timestamps.
- [x] Stored in a single JSON file (`Application Support/Stratum CNC/job-progress.json`, `JobProgressStore`) instead of project data: the machine runs one job at a time, and the coordinator does not know which project the file came from.
- [x] `JobProgress.observe(...)` follows the machine's status reports. Line and percent never go backward. Hold and Pause map to `held` and `suspended`; Alarm to `alarm`; Idle before 100% to `interrupted`.
- [x] Written on every phase change, and at most every 2 s while only the line advances.
- [x] Completion is judged by the firmware's 100%, not by the line count (the reported line is the last motion block, so trailing lines leave it short). When unsure the record is kept.
- [x] Cleared on completion, when a requested run never reached `play` (Idle more than 30 s after `play`, upload or probe failure, disconnect before `play`), and on an explicit discard (`discardProgress()`).
- [x] **Deviation:** an explicit Stop keeps the record as `stopped` instead of clearing it. A stopped job can still be continued with a generated resume file (step 4).
- [x] On launch the record is loaded (`job.progress`); a record still in `starting` is dropped.
- [x] Fingerprint check: `JobProgress.matches(fingerprint:)`. It is not enforced anywhere yet.
- [x] Unit tests: `JobProgressTests`.
- [ ] Not done here: the "offer Resume on launch" UI. It belongs to the resume review sheet in step 7; `job.progress` is what it will read.
- [ ] Not stored yet: active WCS (G54–G59), tool number, stock. The resume preamble is computed from the G-code file itself in step 4; add them here if that turns out not to be enough.
- [ ] Note: `ProjectPathsRegressionTests` and `ProjectPersistenceTests` don't compile (`Project(name:)` initializer), which blocks the whole test target. This predates step 2.

### 3. Safe suspend (app-owned): DONE (`JobCoordinator.suspend()`)
- [x] The machine's own `suspend` stays the core (planner drain, save position, spindle stop). I did **not** replace it with an app-built feed hold + `G53 G0 Z` + `M5` sequence: during a feed hold the firmware's behavior for newly sent moves is unconfirmed, and `suspend` is documented to be safe to leave and to resume from, also after an app restart.
- [x] The app owns what surrounds it: it sends `suspend`, then waits (up to 60 s) until the machine really reports Pause; it gives up and logs on Idle, Alarm, disconnect or timeout. `isSuspending` is published for disabling the button.
- [x] The position is recorded: `progress` becomes `suspended` with the last line from the machine and is written to disk at once.
- [x] Optional park: Settings ▸ Machine ▸ "Park after suspending a job" (off by default) sends the clearance position (`G28`) once suspended. It is opt-in because whether the firmware's `resume` returns to the saved position after the head was moved is unconfirmed.
- [x] Resume and Stop cancel a pending suspend wait.
- [ ] Not done: configurable safe Z / park position. `G28` (the machine's clearance position) is used instead, since it is documented by Makera.
- [ ] Not done: automatic triggers (spindle temperature, alarms). Temperature can be read with `M105`; add a threshold watcher later if wanted.
- [ ] Still delegated: the request goes through `session.suspendJob()` so the library's "paused by the machine" alert is not raised for our own suspend. Moves out with the alert policy in step 8.

### 4. Resume preamble: DONE (`controller/job/GCodeModalState.swift`, `ResumePreamble.swift`)
- [x] `GCodeModalState.scan(lines:beforeLine:)` reads the program from the top and returns the state just before a line: units, G17/18/19 plane, G54–G59, distance mode (G90/G91), modal motion, last F, spindle (M3/M4/M5) and S, airflow (M7/M8/M9), tool (last `M6`), and the work position X/Y/Z (tracked in mm, absolute or relative, inches converted). It also returns the program's highest Z, used as the travel height.
- [x] Handled: words without separators (`T1M6`), `T` after `M6` on the same line, comments, `G53` moves (ignored for work position), `G28`/`G30`/`G92` (position becomes unknown, with a warning for `G92`), canned cycles G81–G89 (flagged, not replayed).
- [x] `ResumePreambleBuilder.build` emits: units, plane, work offset, `G90` → `M6 T<n>` (optional) → `G0 Z<travel>` → `M3/M4 S…` + `G4 P<spin-up>` (only if the spindle was on) → `M7` (if on) → `G0 X Y` → slow plunge `G1 Z… F100` → restores `F`, modal motion, and `G91` if the program was relative.
- [x] `canResume` is false, and no approach move is generated, when X, Y or Z can't be worked out from the program.
- [x] `ResumeFileBuilder.build` produces the complete file: preamble + the program from the resume line to the end. `ResumeFile.lineOffset` / `originalLine(forResumeFileLine:)` map machine line numbers back to the original program.
- [x] `JobCoordinator.resumeWithGeneratedFile(programLines:fileName:fromLine:resumeOptions:runOptions:)` builds the file, refuses with a log message when the position is unknown, uploads it as `resume_<name>` and runs it with the usual pre-run steps. `JobProgress.lineOffset` / `sourceLine` carry the offset, so a later resume of a resume file still points at the right original line.
- [x] Unit tests: `ResumePreambleTests` (state scan, units, relative mode, `G53`, `G28`, canned cycles, preamble contents, resume file, line mapping).
- [ ] Not wired yet: nothing in the UI calls `resumeWithGeneratedFile`, and the `goto` path (`resume(fromLine:)`) does not send the preamble yet. Both belong with the safe restart point (step 5) and the review sheet (step 7).
- [ ] Limits: tool length offset (TLO) after a manual tool change is not handled here (step 6). A resume file's fingerprint is that of the generated file, not of the original program. A restart at line 1 has an unknown position, so it is refused (just run the program normally).
- [ ] The `goto` path would send the same preamble lines while the job is suspended; the Makera docs advise lifting Z first, which the preamble's first move does.

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
