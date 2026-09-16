//
//  CNCCommand+Build.swift
//  MakeraStudio Lite
//
//  Created by Cristian Baluta on 19.08.2026.
//

import Foundation

extension CNCCommand {
    /// The complete command string that can be sent to the machine.
    var command: String {
        switch self {
            case let .rapidMove(x, y, z, a, feed): return build(gcode, x: x, y: y, z: z, a: a, feed: feed)
            case let .linearMove(x, y, z, a, feed): return build(gcode, x: x, y: y, z: z, a: a, feed: feed)
            case let .clockwiseArc(x, y, z, i, j, k, feed): return build(gcode, x: x, y: y, z: z, i: i, j: j, k: k, feed: feed)
            case let .counterClockwiseArc(x, y, z, i, j, k, feed): return build(gcode, x: x, y: y, z: z, i: i, j: j, k: k, feed: feed)
            case let .dwell(seconds): return "\(gcode) P\(format(seconds))"
            case let .setWorkspaceCoordinates(workspace, x, y, z): return build("\(gcode) L2 P\(workspace)", x: x, y: y, z: z)
            case let .probeGrid(r, x, y, a, b, i, j, h):
                var result = "\(gcode) R\(r) X\(format(x)) Y\(format(y)) A\(format(a)) B\(format(b)) H\(format(h))"
                if let i { result += " I\(format(i))" }
                if let j { result += " J\(format(j))" }
                return result
            case let .probe(x, y, z, feed): return build(gcode, x: x, y: y, z: z, feed: feed)
            case let .machineCoordinates(x, y, z, feed): return build("\(gcode) G0", x: x, y: y, z: z, feed: feed)
            case let .setGlobalWorkspace(x, y, z): return build(gcode, x: x, y: y, z: z)
            case let .setMachineHoming(x, y, z): return build(gcode, x: x, y: y, z: z)
            case let .spindleOn(rpm): return "\(gcode) S\(rpm)"
            case let .toolChange(tool): return "\(gcode) T\(tool)"
            case let .feedOverride(percent): return "\(gcode) S\(percent)"
            case let .spindleSpeedOverride(percent): return "\(gcode) S\(percent)"
            case let .laserPowerOverride(percent): return "\(gcode) S\(percent)"
            case let .automaticToolChangeStatus(status): return "\(gcode).\(status.rawValue)"
            case let .internalVacuumOn(percent): return "\(gcode) S\(percent)"
            case let .spindleCoolingFanOn(percent): return "\(gcode) S\(percent)"
            case let .extendedPortOn(percent): return "\(gcode) S\(percent)"
            default: return gcode
        }
    }
}

// MARK: - Formatting

extension CNCCommand {
    func build(_ code: String,
               x: Double? = nil, y: Double? = nil, z: Double? = nil, a: Double? = nil,
               i: Double? = nil, j: Double? = nil, k: Double? = nil, feed: Double? = nil) -> String {

        var result = code
        let values: [(String, Double?)] = [
            ("X", x), ("Y", y), ("Z", z), ("A", a),
            ("I", i), ("J", j), ("K", k), ("F", feed)
        ]

        for (prefix, value) in values {
            if let value {
                result += " \(prefix)\(format(value))"
            }
        }
        return result
    }

    func format(_ value: Double) -> String {
        String(format: "%.3f", value)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }
}
