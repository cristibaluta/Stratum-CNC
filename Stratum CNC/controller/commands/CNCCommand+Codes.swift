//
//  CNCCommand+Codes.swift
//  MakeraStudio Lite
//
//  Created by Cristian Baluta on 19.08.2026.
//

import Foundation

extension CNCCommand {
    /// The base G-code or M-code represented by this command.
    var gcode: String {
        switch self {
            case .rapidMove: "G0"
            case .linearMove: "G1"
            case .clockwiseArc: "G2"
            case .counterClockwiseArc: "G3"
            case .dwell: "G4"
            case .setWorkspaceCoordinates: "G10"
            case .selectXYZPlane: "G17"
            case .selectXZYPlane: "G18"
            case .selectYZXPlane: "G19"
            case .inchMode: "G20"
            case .millimeterMode: "G21"
            case .clearancePosition: "G28"
            case .probeGrid: "G32"
            case .probe: "G38.2"
            case .machineCoordinates: "G53"
            case .workspaceG54: "G54"
            case .absoluteMode: "G90"
            case .relativeMode: "G91"
            case .setGlobalWorkspace: "G92"
            case .clearGlobalWorkspace: "G92.1"
            case .setMachineHoming: "G92.4"
            case .spindleOn: "M3"
            case .spindleOff: "M5"
            case .toolChange: "M6"
            case .airflowOn: "M7"
            case .airflowOff: "M9"
            case .programEnd: "M30"
            case .spindleTemperature: "M105"
            case .feedOverride: "M220"
            case .spindleSpeedOverride: "M223"
            case .enterLaserMode: "M321"
            case .exitLaserMode: "M322"
            case .enterLaserTestMode: "M323"
            case .exitLaserTestMode: "M324"
            case .laserPowerOverride: "M325"
            case .automaticVacuumOn: "M331"
            case .automaticVacuumOff: "M332"
            case .clearBedLeveling: "M370"
            case .displayBedLevelingGrid: "M375.1"
            case .deviceMACAddress: "M482.4"
            case .deviceIPAddress: "M482.5"
            case .automaticToolChangerHome: "M490"
            case .tightenSpindleCollet: "M490.1"
            case .loosenSpindleCollet: "M490.2"
            case .calibrateTool: "M491"
            case .automaticToolChangeStatus: "M497"
            case .pause: "M600"
            case .internalVacuumOn: "M801"
            case .internalVacuumOff: "M802"
            case .spindleCoolingFanOn: "M811"
            case .spindleCoolingFanOff: "M812"
            case .lightOn: "M821"
            case .lightOff: "M822"
            case .toolDetectorLaserOn: "M831"
            case .toolDetectorLaserOff: "M832"
            case .wirelessProbeChargingOn: "M841"
            case .wirelessProbeChargingOff: "M842"
            case .extendedPortOn: "M851"
            case .extendedPortOff: "M852"
            case .beepOn: "M861"
            case .beepOff: "M862"
        }
    }
}
