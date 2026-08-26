//
//  CNCCommand+Codes.swift
//  MakeraStudio Lite
//
//  Created by Cristian Baluta on 19.08.2026.
//

import Foundation

extension CNCCommand {

    /// The base G-code or M-code represented by this command.
    var code: String {
        switch self {

        case .rapidMove:
            return "G0"

        case .linearMove:
            return "G1"

        case .clockwiseArc:
            return "G2"

        case .counterClockwiseArc:
            return "G3"

        case .dwell:
            return "G4"

        case .setWorkspaceCoordinates:
            return "G10"

        case .selectXYZPlane:
            return "G17"

        case .selectXZYPlane:
            return "G18"

        case .selectYZXPlane:
            return "G19"

        case .inchMode:
            return "G20"

        case .millimeterMode:
            return "G21"

        case .clearancePosition:
            return "G28"

        case .probeGrid:
            return "G32"

        case .probe:
            return "G38.2"

        case .machineCoordinates:
            return "G53"

        case .workspaceG54:
            return "G54"

        case .absoluteMode:
            return "G90"

        case .relativeMode:
            return "G91"

        case .setGlobalWorkspace:
            return "G92"

        case .clearGlobalWorkspace:
            return "G92.1"

        case .setMachineHoming:
            return "G92.4"

        case .spindleOn:
            return "M3"

        case .spindleOff:
            return "M5"

        case .toolChange:
            return "M6"

        case .airflowOn:
            return "M7"

        case .airflowOff:
            return "M9"

        case .programEnd:
            return "M30"

        case .spindleTemperature:
            return "M105"

        case .feedOverride:
            return "M220"

        case .spindleSpeedOverride:
            return "M223"

        case .enterLaserMode:
            return "M321"

        case .exitLaserMode:
            return "M322"

        case .enterLaserTestMode:
            return "M323"

        case .exitLaserTestMode:
            return "M324"

        case .laserPowerOverride:
            return "M325"

        case .automaticVacuumOn:
            return "M331"

        case .automaticVacuumOff:
            return "M332"

        case .clearBedLeveling:
            return "M370"

        case .displayBedLevelingGrid:
            return "M375.1"

        case .deviceMACAddress:
            return "M482.4"

        case .deviceIPAddress:
            return "M482.5"

        case .automaticToolChangerHome:
            return "M490"

        case .tightenSpindleCollet:
            return "M490.1"

        case .loosenSpindleCollet:
            return "M490.2"

        case .calibrateTool:
            return "M491"

        case .automaticToolChangeStatus:
            return "M497"

        case .pause:
            return "M600"

        case .internalVacuumOn:
            return "M801"

        case .internalVacuumOff:
            return "M802"

        case .spindleCoolingFanOn:
            return "M811"

        case .spindleCoolingFanOff:
            return "M812"

        case .lightOn:
            return "M821"

        case .lightOff:
            return "M822"

        case .toolDetectorLaserOn:
            return "M831"

        case .toolDetectorLaserOff:
            return "M832"

        case .wirelessProbeChargingOn:
            return "M841"

        case .wirelessProbeChargingOff:
            return "M842"

        case .extendedPortOn:
            return "M851"

        case .extendedPortOff:
            return "M852"

        case .beepOn:
            return "M861"

        case .beepOff:
            return "M862"
        }
    }
}
