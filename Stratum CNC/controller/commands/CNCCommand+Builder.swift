//
//  RapidMoveBuilder.swift
//  MakeraStudio Lite
//
//  Created by Cristian Baluta on 19.08.2026.
//

import Foundation

struct RapidMoveBuilder {

    func with(
        x: Double? = nil,
        y: Double? = nil,
        z: Double? = nil,
        a: Double? = nil,
        feed: Double? = nil
    ) -> CNCCommand {

        .rapidMove(
            x: x,
            y: y,
            z: z,
            a: a,
            feed: feed
        )
    }
}


struct LinearMoveBuilder {

    func with(
        x: Double? = nil,
        y: Double? = nil,
        z: Double? = nil,
        a: Double? = nil,
        feed: Double? = nil
    ) -> CNCCommand {

        .linearMove(
            x: x,
            y: y,
            z: z,
            a: a,
            feed: feed
        )
    }
}


enum ArcDirection {
    case clockwise
    case counterClockwise
}


struct ArcBuilder {

    let direction: ArcDirection

    func with(
        x: Double? = nil,
        y: Double? = nil,
        z: Double? = nil,
        i: Double? = nil,
        j: Double? = nil,
        k: Double? = nil,
        feed: Double? = nil
    ) -> CNCCommand {

        switch direction {

        case .clockwise:
            return .clockwiseArc(
                x: x,
                y: y,
                z: z,
                i: i,
                j: j,
                k: k,
                feed: feed
            )

        case .counterClockwise:
            return .counterClockwiseArc(
                x: x,
                y: y,
                z: z,
                i: i,
                j: j,
                k: k,
                feed: feed
            )
        }
    }
}


struct DwellBuilder {

    func with(seconds: Double) -> CNCCommand {
        .dwell(seconds: seconds)
    }
}


struct WorkspaceBuilder {

    func with(
        workspace: Int,
        x: Double? = nil,
        y: Double? = nil,
        z: Double? = nil
    ) -> CNCCommand {

        .setWorkspaceCoordinates(
            workspace: workspace,
            x: x,
            y: y,
            z: z
        )
    }
}


struct ProbeGridBuilder {

    func with(
        r: Int = 1,
        x: Double,
        y: Double,
        a: Double,
        b: Double,
        i: Double? = nil,
        j: Double? = nil,
        h: Double
    ) -> CNCCommand {

        .probeGrid(
            r: r,
            x: x,
            y: y,
            a: a,
            b: b,
            i: i,
            j: j,
            h: h
        )
    }
}


struct ProbeBuilder {

    func with(
        x: Double? = nil,
        y: Double? = nil,
        z: Double? = nil,
        feed: Double? = nil
    ) -> CNCCommand {

        .probe(
            x: x,
            y: y,
            z: z,
            feed: feed
        )
    }
}


struct MachineCoordinateBuilder {

    func with(
        x: Double? = nil,
        y: Double? = nil,
        z: Double? = nil,
        feed: Double? = nil
    ) -> CNCCommand {

        .machineCoordinates(
            x: x,
            y: y,
            z: z,
            feed: feed
        )
    }
}


struct GlobalWorkspaceBuilder {

    func with(
        x: Double? = nil,
        y: Double? = nil,
        z: Double? = nil
    ) -> CNCCommand {

        .setGlobalWorkspace(
            x: x,
            y: y,
            z: z
        )
    }
}


struct MachineHomingBuilder {

    func with(
        x: Double? = nil,
        y: Double? = nil,
        z: Double? = nil
    ) -> CNCCommand {

        .setMachineHoming(
            x: x,
            y: y,
            z: z
        )
    }
}


struct SpindleBuilder {

    func with(rpm: Int) -> CNCCommand {
        .spindleOn(rpm: rpm)
    }
}


struct ToolChangeBuilder {

    func with(tool: Int) -> CNCCommand {
        .toolChange(tool: tool)
    }
}


struct PercentageBuilder: Sendable {

    private let command: @Sendable (Int) -> CNCCommand

    init(command: @Sendable @escaping (Int) -> CNCCommand) {
        self.command = command
    }

    func with(percent: Int) -> CNCCommand {
        command(
            min(max(percent, 0), 100)
        )
    }
}


struct ATCStatusBuilder {

    func with(status: ATCStatus) -> CNCCommand {
        .automaticToolChangeStatus(
            status: status
        )
    }

    func with(status: Int) -> CNCCommand {
        guard let status = ATCStatus(rawValue: status) else {
            fatalError(
                "Invalid M497 status: \(status)"
            )
        }

        return .automaticToolChangeStatus(
            status: status
        )
    }
}
