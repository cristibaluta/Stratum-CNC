//
//  CNC.swift
//  MakeraStudio Lite
//
//  Created by Cristian Baluta on 19.08.2026.
//

import Foundation

enum CNC {

    // MARK: Motion

    static let rapidMove = RapidMoveBuilder()
    static let linearMove = LinearMoveBuilder()
    static let clockwiseArc = ArcBuilder(direction: .clockwise)
    static let counterClockwiseArc = ArcBuilder(direction: .counterClockwise)

    // MARK: Timing

    static let dwell = DwellBuilder()

    // MARK: Coordinates

    static let setWorkspaceCoordinates = WorkspaceBuilder()
    static let probeGrid = ProbeGridBuilder()
    static let probe = ProbeBuilder()
    static let machineCoordinates = MachineCoordinateBuilder()
    static let setGlobalWorkspace = GlobalWorkspaceBuilder()
    static let setMachineHoming = MachineHomingBuilder()

    // MARK: Spindle

    static let spindleOn = SpindleBuilder()

    // MARK: Tool

    static let toolChange = ToolChangeBuilder()

    // MARK: Overrides

    static let feedOverride = PercentageBuilder(command: { .feedOverride(percent: $0) })
    static let spindleSpeedOverride = PercentageBuilder(command: { .spindleSpeedOverride(percent: $0) })
    static let laserPowerOverride = PercentageBuilder(command: { .laserPowerOverride(percent: $0) })

    // MARK: ATC

    static let automaticToolChangeStatus = ATCStatusBuilder()

    // MARK: Vacuum

    static let internalVacuumOn = PercentageBuilder(command: { .internalVacuumOn(percent: $0) })

    // MARK: Cooling

    static let spindleCoolingFanOn = PercentageBuilder(command: { .spindleCoolingFanOn(percent: $0) })

    // MARK: Extended Port

    static let extendedPortOn = PercentageBuilder(command: { .extendedPortOn(percent: $0) })

    // MARK: Parameterless Commands

    static let selectXYZPlane = CNCCommand.selectXYZPlane
    static let selectXZYPlane = CNCCommand.selectXZYPlane
    static let selectYZXPlane = CNCCommand.selectYZXPlane

    static let inchMode = CNCCommand.inchMode
    static let millimeterMode = CNCCommand.millimeterMode

    static let clearancePosition = CNCCommand.clearancePosition

    static let workspaceG54 = CNCCommand.workspaceG54

    static let absoluteMode = CNCCommand.absoluteMode
    static let relativeMode = CNCCommand.relativeMode

    static let spindleOff = CNCCommand.spindleOff

    static let airflowOn = CNCCommand.airflowOn
    static let airflowOff = CNCCommand.airflowOff

    static let programEnd = CNCCommand.programEnd
    static let spindleTemperature = CNCCommand.spindleTemperature

    static let enterLaserMode = CNCCommand.enterLaserMode
    static let exitLaserMode = CNCCommand.exitLaserMode

    static let enterLaserTestMode = CNCCommand.enterLaserTestMode
    static let exitLaserTestMode = CNCCommand.exitLaserTestMode

    static let automaticVacuumOn = CNCCommand.automaticVacuumOn
    static let automaticVacuumOff = CNCCommand.automaticVacuumOff

    static let clearBedLeveling = CNCCommand.clearBedLeveling
    static let displayBedLevelingGrid = CNCCommand.displayBedLevelingGrid

    static let deviceMACAddress = CNCCommand.deviceMACAddress
    static let deviceIPAddress = CNCCommand.deviceIPAddress

    static let automaticToolChangerHome = CNCCommand.automaticToolChangerHome

    static let tightenSpindleCollet = CNCCommand.tightenSpindleCollet

    static let loosenSpindleCollet = CNCCommand.loosenSpindleCollet

    static let calibrateTool = CNCCommand.calibrateTool

    static let pause = CNCCommand.pause

    static let internalVacuumOff = CNCCommand.internalVacuumOff

    static let spindleCoolingFanOff = CNCCommand.spindleCoolingFanOff

    static let lightOn = CNCCommand.lightOn
    static let lightOff = CNCCommand.lightOff

    static let toolDetectorLaserOn = CNCCommand.toolDetectorLaserOn

    static let toolDetectorLaserOff = CNCCommand.toolDetectorLaserOff

    static let wirelessProbeChargingOn = CNCCommand.wirelessProbeChargingOn

    static let wirelessProbeChargingOff = CNCCommand.wirelessProbeChargingOff

    static let extendedPortOff = CNCCommand.extendedPortOff

    static let beepOn = CNCCommand.beepOn
    static let beepOff = CNCCommand.beepOff
}
