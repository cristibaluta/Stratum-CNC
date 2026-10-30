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

## Steps

### 0. Audit StratumLink (discovery)
- [ ] List everything in `SL.Session` / `SL.JobRunner` related to pause, suspend, resume, resume-from-line, goto, and job progress.
- [ ] Decide for each item: **stay** (pure transport, such as send line, realtime `!` `~` `?`, status) or **move to app**.
- [ ] Define the minimal transport API the app needs: send line and await ack, send realtime byte, status stream, acked-line callback.

### 1. App-side job runner
- [ ] Create `JobController` (app layer, e.g. `controller/job/`) that owns: state (`idle / running / paused / suspended / stopped`), current line, acked line, and streaming.
- [ ] Stream lines itself using the transport API. Keep a planner-buffer-aware window and count `ok` acks.
- [ ] `ControllerModel` calls `JobController` instead of `session.pauseJob()` and the rest.
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
- [ ] Remove the pause, suspend and resume-from-line code from StratumLink (or deprecate it), and drop `lastUploadedRemotePath` as the resume mechanism.
- [ ] Update `README.md` / docs.

## Rules and pitfalls
- Don't trust the machine position after an alarm or soft reset. Re-home first.
- Use stored WCS (G54–G59), never a temporary G92.
- Always include spindle spin-up delay and coolant state in the preamble.
- Plunge slowly at the resume point.

## Order of work
0 → 1 → 2 → 5 → 4 → 3 → 7 → 6 → 8
(1 and 2 first for persistence, 5 and 4 for correct restarts, the rest builds on them.)
