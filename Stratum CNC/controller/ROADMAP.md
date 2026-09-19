# Roadmap: Full Makera Supported-Codes Coverage

Source of truth for codes: https://wiki.makera.com/en/supported-codes

## Current state (as of this audit)

- **Command model is complete.** `CNCCommand` (+`Codes`, +`Commands`) and `CNC+Shortcuts`
  already model every G-code and M-code on the wiki page, with correct string formatting.
- **Wire protocol is solid.** `MachineConnection` + `MakeraFraming` auto-detect plain-text
  Smoothie vs. framed binary Makera protocol, handle CRC16 framing, parse status reports,
  and poll status every second.
- **Discovery works.** `MachineDiscovery` listens for the UDP broadcast and lists machines.
- **G-code visualization works.** `GCodeParser` / `GCodeToolpath*` / `GCodeViewer` /
  `BezierPathFlattener` parse and render G0/G1/G2/G3 motion, absolute/relative modes, arcs.
- **Jogging is fully wired.** `PanelJog` → `JogController`, step and hold modes, game
  controller support.

### The real gap: modeled ≠ wired up

Only **6 of the ~65 modeled `CNCCommand` cases** are actually called from the UI today:
`lightOn`, `lightOff`, `spindleOn`, `spindleOff`, `probe` (x/y/z variants). Everything else —
tool change, laser mode, vacuum, cooling fan, ATC homing/collet, bed leveling, overrides,
device info, extended port, beep, plane/units selection, workspace offsets — has a correct
command builder but no button/panel/menu calls it.

Also: `G92.1` (`clearGlobalWorkspace`) exists in `CNCCommand` but was never added to
`CNC+Shortcuts`, so it isn't reachable even from code.

### The bigger gap: no job execution

`GCodeViewer.swift`'s transport bar (Play / Pause / Stop / "Send to Machine") has **empty
button actions** — it's a visual stub. `MakeraFraming` already defines the file-transfer
packet types the firmware expects for receiving a job (`ptypeFileStart/MD5/View/Data/End/
Cancel/Retry`, 0xB0–0xB6), but `MachineConnection.send()` never builds them, and incoming
frames of those types are explicitly skipped in `handleMakeraBytes()`. Today the app can
visualize a file, jog manually, and send one MDI line at a time — it cannot run a loaded
job on the machine. There's also no `goto <line>` wiring to resume from a specific line.

### Console commands (bottom of the wiki page)

`ap`, `wlan`, `time`, `version`, `enable_4th`/`disable_4th`/`check_4th`, beep config —
none are modeled or exposed in UI (though raw text can be sent via MDI today).

---

## Phase 1 — Job execution (highest priority)

The app can't actually run a G-code file on the machine yet. This is the core missing feature.

- [x] 1.1 Wire Play/Pause/Stop in `GCodeViewer`'s `commandBar` to real actions
- [x] 1.2 Implement file-transfer framing (`ptypeFileStart`/`MD5`/`Data`/`End`) in
      `MachineConnection` to upload `.nc` files, matching `Carvera_Controller`'s
      `WIFIStream.py`.
      Landed as `GCodeUploader` (+ `MachineConnection.sendFileFrame`/`sendRawBytes`,
      `MakeraFraming.FileTransfer`). Real hardware can't stream a job line-by-line —
      `GCodeJobRunner`/1.1 is now MDI/macro-only — so "Send to Machine" uploads the
      whole file to the SD card and machine-side `play <path>` runs it from there,
      confirmed against Carvera_Controller issue #811's MDI trail (`upload <path>`
      as the trigger command, plain-text ack/error lines) and Smoothieware's
      documented `.smoothie`-protocol `upload`/Ctrl-D flow. The framed-protocol
      payload shapes for `ptypeFileStart`/`ptypeFileMD5` (see
      `MakeraFraming.FileTransfer`) are a best-effort reconstruction, not read
      from `WIFIStream.py` itself (wasn't accessible while writing this) — worth
      checking against a real packet capture before relying on it for anything
      valuable.
- [x] 1.3 Add realtime feed-hold (`!`) / resume (`~`) / soft-reset for pause/resume/abort of a
      running job.
      Landed as `MachineRealtimeCommand` + `MachineConnection.sendRealtime(_:)` (single bytes,
      wrapped in a `ptypeCtrlSingle` frame under the Makera protocol, same as `?`), with
      `ControllerModel.pauseJob`/`resumeJob`/`stopJob` on top and the viewer's pause/stop
      buttons wired to them. Enablement follows the machine's reported state
      (`MakeraMachineStatus.isRunning`/`isHeld`/`isBusy`), so it also works for a job that was
      started or held from the machine itself. `!`, `~` and `^X` also work from the MDI box and
      the command palette. Also fixed a `GCodeJobRunner` race this made likely: resuming while
      the held line's `ok` was still outstanding sent a second line.
      Checked against the reference sources (Carvera_Controller `Controller.py`/`makera.kv`,
      Carvera_Community_Firmware `Kernel.cpp`/`Player.cpp`) — not against real hardware:
      - `!` `~` `^X` match the reference's `feedholdCommand`/`cyclestartCommand`/`estopCommand`.
      - `Pause` is a real state (the firmware's SUSPEND), not just a defensive guess. It comes
        from the console `suspend` command, which is *not* a feed-hold: it waits for the planner
        to drain, saves position and stops the spindle. It's resumed with the console `resume`,
        not `~` — `resumeJob()` now picks the right one for `Hold` vs `Pause` (the first cut of
        1.3 sent `~` for both, which does nothing to a suspended machine).
      - Our Pause button is the immediate feed-hold, per this item. The reference also offers
        `suspend`/`resume` ("pause at next safe opportunity, allow MDI") as a separate button.
      - Our Stop is a `^X` soft-reset (immediate; not resumable; typically leaves ALARM until
        Unlock, which is left manual on purpose). The reference splits this in two: a graceful
        console `abort` ("Abort File Now": saves last progress, drains the queue, ends the file)
        and a separate E-Stop for `^X`. Adding `abort` alongside is an open option.
- [x] 1.4 Track & display job progress (current line, % complete) from status reports.
      Landed as `MakeraPlayback` (the status report's `P:` field, parsed in
      `MakeraMachineStatus.parse`) with `MakeraMachineStatus.activeJob`/`lastJob`. `GCodeViewer`
      shows a progress bar + line + percent + elapsed above the transport bar, and the machine's
      executing line now drives the G-code table's highlight (and auto-scroll) while a job is
      active. Sources: Kernel.cpp `get_query_string()` / Player.cpp `get_progress`, and how
      Carvera_Controller reads them.
      - Field layout is `P:played_lines,percent,elapsed_secs,is_playing,parsed_lines`; older
        firmware stops after 3 values (then "playing" = line > 0, as the reference does).
      - The line is a 1-based *physical* file line (blanks/comments count), so it matches the
        table row for a file uploaded verbatim. It's the executing motion block while running.
        `parsed_lines` (how far the firmware has read ahead) is parsed but not displayed.
      - `percent` is by bytes read, not lines executed, so it leads the executing line a little
        and isn't linear in lines. It's still the number from the report itself; a `line ÷ total
        lines` percent (what the reference draws) needs the file's line count and knowing which
        file is playing, which the report doesn't say.
      - `is_playing` is 0 while a job is *suspended* even though it's alive, so `activeJob` also
        counts the `Pause` state. After a job ends or is aborted the firmware keeps reporting its
        frozen values until the next job; `lastJob` surfaces them ("Last job: line N…"), which is
        also where 1.5 will read the resume line from.
      - Known limitation: the report has no filename, so the table highlight assumes the loaded
        document is the one playing (out-of-range lines are ignored). A job started from the
        machine's own controls will highlight whatever row shares that number.
- [x] 1.5 Wire up `goto <line>` to resume from a specific line after a pause
      Landed as `ControllerModel.resumeJob(fromLine:)` (the old no-arg `resumeJob()` now just
      calls it with `nil`) plus a "Resume from Line N" button in `GCodeViewer`'s command bar,
      shown only while held and only once `ControllerModel.lastUploadedRemotePath` (new, set
      from `uploader.onCompleted`) says a file's actually on the SD card to seek in. The target
      line is whatever row was last tapped in the G-code table (`GCodeStore.requestedLine`),
      falling back to the scrub position.
      `goto <line>` is sent before, not instead of, the same feed-hold/`suspend` resume 1.3
      already sends — it only repositions Player.cpp's read pointer for whatever resumes next.
      Not confirmed against Player.cpp's console-command source or real hardware (wasn't
      accessible while writing this) — matches the roadmap's own phrasing and the shape of the
      other file-position console commands (`play <path>`), but worth checking against a real
      machine before relying on it, especially whether `goto` needs the path repeated
      (`goto <path> <line>`) rather than a bare line number.

## Phase 2 — Wire up already-modeled commands

~55 of the ~65 modeled `CNCCommand` cases have zero UI. Low-risk, high-value: the string
building is already correct, this is just adding buttons/panels.

- [ ] 2.1 Tool change: M6 in an ATC panel (tighten/loosen collet M490.1/.2, home M490,
      calibrate M491, status M497)
- [ ] 2.2 Spindle/vacuum/cooling: M801/802, M811/812, M331/332, extended port M851/852
- [ ] 2.3 Laser mode: M321–M325 as a dedicated mode toggle with power override
- [ ] 2.4 Overrides: feed (M220) and spindle (M223) sliders, likely near `PanelSpindle`
- [ ] 2.5 Coordinate/plane setup: G17–G21 plane & units, G54 workspace select, G10/G92/G92.1/
      G92.4 offsets in `PanelCoordinate`
- [ ] 2.6 Bed leveling: G32 probe grid + M370 clear + M375.1 display, as a guided workflow
- [ ] 2.7 Fix the orphaned G92.1 (add to `CNC+Shortcuts`)

## Phase 3 — Console commands & machine setup

The bottom half of the wiki page (non-G/M console commands) isn't modeled at all.

- [ ] 3.1 Wi-Fi setup panel: `ap ssid/password/enable/disable`, `wlan` scan/connect/disconnect
- [ ] 3.2 Machine info panel: `version`, `time`, M482.4/M482.5 (MAC/IP)
- [ ] 3.3 4th axis panel: `enable_4th`/`disable_4th`/`check_4th`
- [ ] 3.4 Beep toggle (M861/862 already modeled; add `config-set` beep command)

## Phase 4 — Probing workflow polish

`PanelProbe` exists but is minimal — 4 buttons with mostly duplicate/hardcoded values.

- [ ] 4.1 Fix "Auto Z" button, which currently sends the exact same command as "Probe Z"
- [ ] 4.2 Make probe distances/feeds configurable instead of hardcoded (-10, 10, 50)
- [ ] 4.3 Build a real tool-length-offset workflow around M491/`calibrateTool`
- [ ] 4.4 Surface probe results (trigger position) back into the work coordinate panel
