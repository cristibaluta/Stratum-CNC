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

    /// Canvas/render state, deliberately kept off `ControllerModel` itself —
    /// see `CanvasSceneModel`'s doc comment for why: mutating it on every
    /// scrub tick would otherwise re-render every panel that shares this
    /// `ControllerModel` instance.
    let scene = CanvasSceneModel()

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

    /// `recordInHistory: false` keeps high-frequency, machine-generated lines
    /// (jog steps) from pushing the commands the user actually typed out of
    /// the 10-entry MDI history. They still show up in the terminal log.
    func sendRawCommand(_ command: String, recordInHistory: Bool = true) {
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

        if recordInHistory {
            addToHistory(command)
        }
        connection.send(command)
    }

    // MARK: - Jogging

    /// A move requested from `PanelJog`. Kept as an explicit choice between
    /// relative and absolute because `G0` alone is always interpreted in
    /// whatever distance mode the machine happens to be in (G90 by default),
    /// so "move X by +0.1" and "go to X 0.1" can't share one command.
    enum JogRequest {
        /// Move each given axis by this distance from where it is now
        /// (mm for X/Y/Z, degrees for A).
        case relative(x: Double?, y: Double?, z: Double?, a: Double?)
        /// Move each given axis to this work coordinate.
        case absolute(x: Double?, y: Double?, z: Double?, a: Double?)
    }

    func jog(_ request: JogRequest) {
        switch request {
        case let .relative(x, y, z, a):
            guard x != nil || y != nil || z != nil || a != nil else {
                return
            }
            // Relative mode is switched on and back off within the same
            // line, so a jog can never leave the machine in G91 for
            // whatever gets sent next (an absolute move, a job line…), even
            // if the connection drops right after.
            let move = CNC.rapidMove.with(x: x, y: y, z: z, a: a).command
            sendRawCommand("\(CNC.relativeMode.command) \(move) \(CNC.absoluteMode.command)",
                           recordInHistory: false)

        case let .absolute(x, y, z, a):
            guard x != nil || y != nil || z != nil || a != nil else {
                return
            }
            sendRawCommand(CNC.rapidMove.with(x: x, y: y, z: z, a: a).command,
                           recordInHistory: false)
        }
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
