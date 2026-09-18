//
//  AppModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI
import simd

@MainActor
class ControllerModel: ObservableObject {

    @Published var discovery = MachineDiscovery()
    @Published var connection = MachineConnection()
    @Published var selectedMachine: MakeraMachine?

    @Published var mdiInput = ""
    @Published var commandHistory: [String] = []
    @Published var historyIndex: Int?

    @Published var selectedFeedOverride: Int = 100
    @Published var spindleRPM = "12000"

    @Published var isGCodeImporterPresented = false
    @Published var isShowingCommandPalette = false
    @Published var isLightOn = false
    @Published var terminalAutoScroll = true

    /// Plain CPU-side data describing what the 3D canvas should draw. No Metal
    /// types here — MetalRenderer is the only thing that turns this into GPU buffers.
    @Published var renderObjects: [RenderObject] = RenderObject.defaultScene()

    /// Rebuilds just the stock wireframe from `stock`'s shape and dimensions,
    /// leaving the rest of the scene (axes, toolpath preview, position
    /// marker) untouched. `ControllerView` calls this whenever
    /// `CAMModel.selectedStockMaterial` changes, so the box drawn here always
    /// matches whatever was last set in `MaterialPanelView`.
    func updateStock(_ stock: StockMaterial) {
        renderObjects.updating(.stockBox(for: stock))
    }

    /// Rebuilds the toolpath preview from a freshly (re)parsed G-code file,
    /// replacing whichever rapid/cutting objects were drawn before — axes,
    /// stock, and the position marker are untouched. `ControllerView` calls
    /// this whenever `GCodeStore.document.toolpathSegments` changes, so the
    /// canvas always shows the currently loaded program.
    func updateToolpath(_ segments: [ToolpathSegment]) {
        renderObjects.replacing(roles: [.toolpathRapid, .toolpathCutting],
                                with: RenderObject.toolpath(from: segments))
    }

    /// Narrows how much of the *already-loaded* rapid/cutting toolpath is
    /// drawn — the scrubber's fast path. Unlike `updateToolpath`, this never
    /// re-tessellates: it mutates `visibleVertexCount` in place on the
    /// existing `.toolpathRapid`/`.toolpathCutting` objects, which keeps
    /// their `id`s stable, which is what lets `MetalRenderer.updateGeometry`
    /// reuse their GPU buffers instead of rebuilding them. Cheap enough to
    /// call on every slider tick. Pass the counts from
    /// `NCFileDocument.toolpathVertexCounts(upTo:)`, which is the O(1)
    /// counterpart to the segment slice `updateToolpath` expects.
    func setToolpathVisibleVertexCounts(rapid: Int, cutting: Int) {
        renderObjects.settingVisibleVertexCount(rapid, forRole: .toolpathRapid)
        renderObjects.settingVisibleVertexCount(cutting, forRole: .toolpathCutting)
    }

    /// Real diameter/length of the tool currently drawn on the canvas, in
    /// millimeters. Defaults to a common 1/8" end mill; set these from the
    /// active `Tool` (`ToolLibrary`/`ToolsStore`) once tool selection is
    /// tracked for a running job, and `updateToolPosition` will pick up the
    /// new size on the next call.
    @Published var toolDiameter: Double = 3.175
    @Published var toolLength: Double = 40

    /// Rebuilds the cutter wireframe at `point` (the machine's current
    /// work position) using `toolDiameter`/`toolLength`, replacing whatever
    /// was drawn there before — axes, stock, and the toolpath preview are
    /// untouched. Call this whenever the machine reports a new position.
    func updateToolPosition(_ point: SIMD3<Float>) {
        renderObjects.updating(.tool(at: point, diameter: toolDiameter, length: toolLength))
    }

    func sendCommand(_ command: CNCCommand) {
        sendRawCommand(command.command)
    }

    func sendPaletteCommand(_ paletteCommand: PaletteCommand) {
        if let command = paletteCommand.command {
            sendCommand(command)
        } else {
            sendRawCommand(paletteCommand.rawCommand)
        }
    }

    func sendRawCommand(_ command: String) {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !command.isEmpty else {
            return
        }

        guard connection.isConnected else {
            return
        }

        // "?" is a realtime status-query byte, not a queued line/frame —
        // route it through the protocol-aware realtime path so it works
        // correctly under both the plain-text and framed wire protocols.
        if command == statusCommand {
            connection.requestStatus()
            return
        }

        addToHistory(command)
        connection.send(command)
    }

    // MARK: - Raw commands not modeled by CNCCommand

    /// Grbl/Smoothieware-style homing command. Confirmed against
    /// Carvera_Controller/carveracontroller/Controller.py -> home().
    let homeCommand = "$H"

    /// Grbl/Smoothieware-style alarm-clear/unlock command. Confirmed against
    /// Controller.py -> unlock().
    let unlockCommand = "$X"

    /// Realtime status query byte — handled specially in sendRawCommand(),
    /// since it needs the protocol-aware realtime path, not a queued line.
    let statusCommand = "?"

    /// Builds a "set current axis position as zero" command. Matches the
    /// reference app's wcs_set(): G10 L20 P0 sets the active work coordinate
    /// system offset so the machine's *current* physical position reads as
    /// the given value (0) on the specified axes. (CNCCommand doesn't model
    /// this yet — G92 would only be a temporary offset, not equivalent.)
    func zeroCommand(x: Bool = false, y: Bool = false, z: Bool = false) -> String {
        var command = "G10L20P0"
        if x { command += "X0" }
        if y { command += "Y0" }
        if z { command += "Z0" }
        return command
    }

    // MARK: - Sending Commands

    func toggleLight() {
        let command = isLightOn ? CNC.lightOff : CNC.lightOn
        sendCommand(command)
        isLightOn.toggle()
    }

    func sendMDI() {
        let command = mdiInput
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !command.isEmpty else {
            return
        }

        sendRawCommand(command)

        mdiInput = ""
        historyIndex = nil
    }



    // MARK: - Command History

    func addToHistory(_ command: String) {
        if commandHistory.last == command {
            return
        }

        commandHistory.removeAll {
            $0 == command
        }

        commandHistory.append(command)

        if commandHistory.count > 10 {
            commandHistory.removeFirst(
                commandHistory.count - 10
            )
        }
    }

    func historyPrevious() {
        guard !commandHistory.isEmpty else {
            return
        }

        if let index = historyIndex {
            historyIndex = max(0, index - 1)
        } else {
            historyIndex = commandHistory.count - 1
        }

        if let index = historyIndex {
            mdiInput = commandHistory[index]
        }
    }

    func historyNext() {
        guard let index = historyIndex else {
            return
        }

        if index + 1 < commandHistory.count {
            historyIndex = index + 1
            mdiInput = commandHistory[index + 1]
        } else {
            historyIndex = nil
            mdiInput = ""
        }
    }

    // MARK: - Terminal

    func clearTerminal() {
        connection.clearLogs()
    }

    var favoriteCommands: [PaletteCommand] {
        [
            PaletteCommand(title: "Get status", rawCommand: statusCommand),
            PaletteCommand(title: "Spindle stop", command: CNC.spindleOff),
            PaletteCommand(title: "Home", rawCommand: homeCommand),
            PaletteCommand(title: "Set XYZ zero", rawCommand: zeroCommand(x: true, y: true, z: true)),
            PaletteCommand(title: "Light on", command: CNC.lightOn),
            PaletteCommand(title: "Light off", command: CNC.lightOff)
        ]
    }
}
