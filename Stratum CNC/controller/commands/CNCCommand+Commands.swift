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

        case let .rapidMove(x, y, z, a, feed):
            return build(
                code,
                x: x,
                y: y,
                z: z,
                a: a,
                feed: feed
            )

        case let .linearMove(x, y, z, a, feed):
            return build(
                code,
                x: x,
                y: y,
                z: z,
                a: a,
                feed: feed
            )

        case let .clockwiseArc(x, y, z, i, j, k, feed):
            return build(
                code,
                x: x,
                y: y,
                z: z,
                i: i,
                j: j,
                k: k,
                feed: feed
            )

        case let .counterClockwiseArc(x, y, z, i, j, k, feed):
            return build(
                code,
                x: x,
                y: y,
                z: z,
                i: i,
                j: j,
                k: k,
                feed: feed
            )

        case let .dwell(seconds):
            return "\(code) P\(format(seconds))"

        case let .setWorkspaceCoordinates(workspace, x, y, z):
            return build(
                "\(code) L2 P\(workspace)",
                x: x,
                y: y,
                z: z
            )

        case let .probeGrid(r, x, y, a, b, i, j, h):
            var result =
                "\(code)" +
                " R\(r)" +
                " X\(format(x))" +
                " Y\(format(y))" +
                " A\(format(a))" +
                " B\(format(b))" +
                " H\(format(h))"

            if let i {
                result += " I\(format(i))"
            }

            if let j {
                result += " J\(format(j))"
            }

            return result

        case let .probe(x, y, z, feed):
            return build(
                code,
                x: x,
                y: y,
                z: z,
                feed: feed
            )

        case let .machineCoordinates(x, y, z, feed):
            return build(
                "\(code) G0",
                x: x,
                y: y,
                z: z,
                feed: feed
            )

        case let .setGlobalWorkspace(x, y, z):
            return build(
                code,
                x: x,
                y: y,
                z: z
            )

        case let .setMachineHoming(x, y, z):
            return build(
                code,
                x: x,
                y: y,
                z: z
            )

        case let .spindleOn(rpm):
            return "\(code) S\(rpm)"

        case let .toolChange(tool):
            return "\(code) T\(tool)"

        case let .feedOverride(percent):
            return "\(code) S\(percent)"

        case let .spindleSpeedOverride(percent):
            return "\(code) S\(percent)"

        case let .laserPowerOverride(percent):
            return "\(code) S\(percent)"

        case let .automaticToolChangeStatus(status):
            return "\(code).\(status.rawValue)"

        case let .internalVacuumOn(percent):
            return "\(code) S\(percent)"

        case let .spindleCoolingFanOn(percent):
            return "\(code) S\(percent)"

        case let .extendedPortOn(percent):
            return "\(code) S\(percent)"

        default:
            return code

        }
    }
}

// MARK: - Formatting

extension CNCCommand {

    func build(
        _ code: String,
        x: Double? = nil,
        y: Double? = nil,
        z: Double? = nil,
        a: Double? = nil,
        i: Double? = nil,
        j: Double? = nil,
        k: Double? = nil,
        feed: Double? = nil
    ) -> String {

        var result = code

        if let x {
            result += " X\(format(x))"
        }

        if let y {
            result += " Y\(format(y))"
        }

        if let z {
            result += " Z\(format(z))"
        }

        if let a {
            result += " A\(format(a))"
        }

        if let i {
            result += " I\(format(i))"
        }

        if let j {
            result += " J\(format(j))"
        }

        if let k {
            result += " K\(format(k))"
        }

        if let feed {
            result += " F\(format(feed))"
        }

        return result
    }

    func format(_ value: Double) -> String {
        String(format: "%.3f", value)
            .replacingOccurrences(
                of: "0+$",
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "\\.$",
                with: "",
                options: .regularExpression
            )
    }
}
