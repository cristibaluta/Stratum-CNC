//
//  ControllerModel+Probe.swift
//  Stratum CNC
//
//  The three things the probing result step does to the machine and the
//  canvas: write the origin, undo it, and move to it.
//

import Foundation

extension ControllerModel {

    /// The lines the app would send at the start of a run if the canvas job
    /// offset were `offset`. Shown in the result step so the person can see
    /// whether a run would keep or replace the probed origin.
    func runStartLines(forProbed result: ProbeResult, previousOffset: SIMD2<Float>) -> [String] {
        jobOriginCommands(for: probedXYOffset(result, current: previousOffset))
    }

    /// The canvas job offset that puts the work origin where `result` found it.
    func probedXYOffset(_ result: ProbeResult, current: SIMD2<Float>) -> SIMD2<Float> {
        let anchor = scene.machineLayout.activeAnchor
        let offset = result.xyOffset(anchor: SIMD2(Double(anchor.x), Double(anchor.y)),
                                     current: SIMD2(Double(current.x), Double(current.y)))
        return SIMD2(Float(offset.x), Float(offset.y))
    }

    /// Writes the probed XY origin to the machine (`G10 L2`, absolute) and
    /// moves the canvas job offset with it. Without the second part, starting
    /// a run would send the old offset and replace the probed origin.
    ///
    /// `previousMachineOrigin` is the origin before the cycle ran, kept so the
    /// change can be undone.
    @discardableResult
    func applyProbedOrigin(_ result: ProbeResult,
                           workCoordinateSystem: Int,
                           previousMachineOrigin: SIMD2<Double>?) -> ProbeAppliedOrigin? {
        guard let command = result.originCommand(workCoordinateSystem: workCoordinateSystem) else { return nil }

        let previousOffset = scene.xyOffset
        connection.appendLog("3D probe: \(command)")
        sendRawCommand(command)
        scene.xyOffset = probedXYOffset(result, current: previousOffset)

        return ProbeAppliedOrigin(workCoordinateSystem: workCoordinateSystem,
                                  changedX: result.originX != nil,
                                  changedY: result.originY != nil,
                                  previousXYOffset: previousOffset,
                                  previousMachineOrigin: previousMachineOrigin)
    }

    /// Puts back the origin and the canvas offset that Apply replaced. Z is
    /// not touched: it was zeroed during the cycle.
    func revertProbedOrigin(_ applied: ProbeAppliedOrigin) {
        if let command = applied.revertCommand {
            connection.appendLog("3D probe: \(command)")
            sendRawCommand(command)
        }
        scene.xyOffset = applied.previousXYOffset
    }

    /// Moves over the probed origin at the current height. The cycle ends at
    /// its safe height above the stock, so this is only for right after it.
    func moveOverProbedOrigin(_ result: ProbeResult) {
        guard let x = result.originX, let y = result.originY else { return }
        sendRawCommand("G90")
        sendRawCommand("G53 G0 X\(ProbeCycleBuilder.number(x)) Y\(ProbeCycleBuilder.number(y))")
    }
}
