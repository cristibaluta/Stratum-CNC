//
//  CNCCommand.swift
//  MakeraStudio Lite
//
//  Created by Cristian Baluta on 19.08.2026.
//
import Foundation

enum CNCCommand {

    // MARK: G Codes

    /// Move to the given coordinates. It is used to go to a new area without
    /// cutting, it is also called a "rapid" move. Note that the F parameter
    /// can be used here and is remembered by subsequent commands.
    ///
    /// Example: G0 X10 Y5 F100
    case rapidMove(
        x: Double?,
        y: Double?,
        z: Double?,
        a: Double?,
        feed: Double?
    )

    /// Move to the given coordinates.
    /// Takes the same F parameter as G0.
    ///
    /// Example: G1 X20 Y2.3 F200
    case linearMove(
        x: Double?,
        y: Double?,
        z: Double?,
        a: Double?,
        feed: Double?
    )

    /// Clockwise circular motion: go to point with coordinates XYZ while
    /// rotating around a point with relative coordinates IJ.
    ///
    /// Example: G2 X10 J5
    case clockwiseArc(
        x: Double?,
        y: Double?,
        z: Double?,
        i: Double?,
        j: Double?,
        k: Double?,
        feed: Double?
    )

    /// Counter-clockwise motion: see G2 for the corresponding clockwise motion.
    ///
    /// Example: G3 Y5 X10 I2
    case counterClockwiseArc(
        x: Double?,
        y: Double?,
        z: Double?,
        i: Double?,
        j: Double?,
        k: Double?,
        feed: Double?
    )

    /// Dwell for the specified number of seconds.
    ///
    /// Example: G4 P1
    case dwell(seconds: Double)

    /// Set workspace coordinates.
    ///
    /// Example: G10 L2 P1 X0
    case setWorkspaceCoordinates(
        workspace: Int,
        x: Double?,
        y: Double?,
        z: Double?
    )

    /// Select XYZ plane. Command is modal.
    ///
    /// Example: G17
    case selectXYZPlane

    /// Select XZY plane. Command is modal.
    ///
    /// Example: G18
    case selectXZYPlane

    /// Select YZX plane. Command is modal.
    ///
    /// Example: G19
    case selectYZXPlane

    /// Inch mode. Passed coordinates are considered to be inches and are
    /// internally translated to millimeters.
    ///
    /// Example: G20
    case inchMode

    /// Millimeter mode (default). Passed coordinates are considered to be
    /// millimeters.
    ///
    /// Example: G21
    case millimeterMode

    /// G28 means go to the clearance position on the Carvera.
    ///
    /// Example: G28
    case clearancePosition

    /// Probe the grid and turn compensation on. This remains in effect until
    /// reset or M370. X and Y are the start position, A and B are the width
    /// and length, I and J are the grid size, and H is the height.
    ///
    /// Example: G32 R1 X0 Y0 A10 B10 H2
    case probeGrid(
        r: Int,
        x: Double,
        y: Double,
        a: Double,
        b: Double,
        i: Double?,
        j: Double?,
        h: Double
    )

    /// Standard probe commands implemented as documented by Makera.
    ///
    /// Example: G38.2 Z-10
    case probe(
        x: Double?,
        y: Double?,
        z: Double?,
        feed: Double?
    )

    /// Must be on a line by itself OR the first G code on a line.
    /// The directly following G0/G1 will be executed in MCS coordinates.
    ///
    /// Example: G53 G0 X0 Y0
    case machineCoordinates(
        x: Double?,
        y: Double?,
        z: Double?,
        feed: Double?
    )

    /// Use workspace coordinates.
    ///
    /// Example: G54
    case workspaceG54

    /// Absolute mode (default). Command is modal.
    ///
    /// Example: G90
    case absoluteMode

    /// Relative mode. Command is modal.
    ///
    /// Example: G91
    case relativeMode

    /// Set global workspace coordinate system to specified coordinates.
    ///
    /// Example: G92 X0 Y0 Z0
    case setGlobalWorkspace(
        x: Double?,
        y: Double?,
        z: Double?
    )

    /// Clear the G92 offsets.
    ///
    /// Example: G92.1
    case clearGlobalWorkspace

    /// Manually set homing (MCS) for XYZ.
    ///
    /// Example: G92.4 X0 Y0 Z0
    case setMachineHoming(
        x: Double?,
        y: Double?,
        z: Double?
    )


    // MARK: M Codes

    /// Starts the spindle. The S parameter sets the speed in rotations
    /// per minute.
    ///
    /// Example: M3 S5000
    case spindleOn(rpm: Int)

    /// Stops the spindle.
    ///
    /// Example: M5
    case spindleOff

    /// Auto tool change. T0 indicates wireless probe, T-1 indicates None.
    ///
    /// Example: M6 T1
    case toolChange(tool: Int)

    /// Starts the airflow.
    ///
    /// Example: M7
    case airflowOn

    /// Stops the airflow.
    ///
    /// Example: M9
    case airflowOff

    /// End of the program, no action on the Carvera.
    ///
    /// Example: M30
    case programEnd

    /// Read the current spindle temperature.
    ///
    /// Example: M105
    case spindleTemperature

    /// Set feed speed factor override percentage.
    ///
    /// Example: M220 S50
    case feedOverride(percent: Int)

    /// Set spindle speed factor override percentage.
    ///
    /// Example: M223 S80
    case spindleSpeedOverride(percent: Int)

    /// Enter the laser mode. The machine will drop the current tool
    /// automatically and calibrate the spindle collet to set the laser
    /// offset to the working surface.
    ///
    /// Example: M321
    case enterLaserMode

    /// Exit the laser mode.
    ///
    /// Example: M322
    case exitLaserMode

    /// Enter the laser test mode. The laser module will be supplied a very
    /// low power, usually used for re-focusing the laser.
    ///
    /// Example: M323
    case enterLaserTestMode

    /// Exit the laser test mode.
    ///
    /// Example: M324
    case exitLaserTestMode

    /// Set laser power factor override percentage.
    ///
    /// Example: M325 S50
    case laserPowerOverride(percent: Int)

    /// Turn on the auto vacuum mode. If on, the vacuum will be turned on
    /// automatically when the spindle is running and turned off when the
    /// spindle is not running.
    ///
    /// Example: M331
    case automaticVacuumOn

    /// Turn off the auto vacuum mode.
    ///
    /// Example: M332
    case automaticVacuumOff

    /// Clear the auto bed levelling data and disable the compensation
    /// until G32 is run again.
    ///
    /// Example: M370
    case clearBedLeveling

    /// Display the current bed leveling grid data in the MDI window.
    ///
    /// Example: M375.1
    case displayBedLevelingGrid

    /// Retrieve device MAC address.
    ///
    /// Example: M482.4
    case deviceMACAddress

    /// Retrieve device IP address.
    ///
    /// Example: M482.5
    case deviceIPAddress

    /// Execute the ATC homing process. Homing will be executed automatically
    /// when issuing M490.1 or M490.2 if needed.
    ///
    /// Example: M490
    case automaticToolChangerHome

    /// Tightens the spindle collet to secure a new tool in the spindle.
    ///
    /// Example: M490.1
    case tightenSpindleCollet

    /// Loosens the spindle collet and drops the current milling bit.
    ///
    /// Example: M490.2
    case loosenSpindleCollet

    /// Execute a calibration, and the TLO (tool length offset) for the
    /// current tool will be reset.
    ///
    /// Example: M491
    case calibrateTool

    /// Set the status of automatic tool change.
    ///
    /// Subcode 1: Drop tool
    /// Subcode 2: Pick tool
    /// Subcode 3: Calibrate
    /// Subcode 4: Margin
    /// Subcode 5: Zprobe
    /// Subcode 6: Autolevel
    /// Subcode 7: Done
    /// Subcode 0: None
    ///
    /// Example: M497.1
    case automaticToolChangeStatus(status: ATCStatus)

    /// Pauses the machine and waits for a resume command to continue.
    ///
    /// Example: M600
    case pause

    /// Turn on the internal vacuum (Carvera). The S parameter sets the
    /// power of the vacuum. S100 = 100%.
    ///
    /// Example: M801 S100
    case internalVacuumOn(percent: Int)

    /// Turn off the internal vacuum (Carvera).
    ///
    /// Example: M802
    case internalVacuumOff

    /// Turn on the spindle cooling fan. The S parameter sets the power
    /// of the fan.
    ///
    /// Example: M811 S100
    case spindleCoolingFanOn(percent: Int)

    /// Turn off the spindle cooling fan.
    ///
    /// Example: M812
    case spindleCoolingFanOff

    /// Turn on the light.
    ///
    /// Example: M821
    case lightOn

    /// Turn off the light.
    ///
    /// Example: M822
    case lightOff

    /// Turn on the tool detector sensor laser.
    ///
    /// Example: M831
    case toolDetectorLaserOn

    /// Turn off the tool detector sensor laser.
    ///
    /// Example: M832
    case toolDetectorLaserOff

    /// Turn on the wireless probe charging power.
    ///
    /// Example: M841
    case wirelessProbeChargingOn

    /// Turn off the wireless probe charging power.
    ///
    /// Example: M842
    case wirelessProbeChargingOff

    /// Turn on the extended port power. The S parameter sets the PWM
    /// output of the port, such as the suction power.
    ///
    /// Example: M851 S50
    case extendedPortOn(percent: Int)

    /// Turn off the extended port power.
    ///
    /// Example: M852
    case extendedPortOff

    /// Turn on the beep. Only for Carvera Air.
    ///
    /// Example: M861
    case beepOn

    /// Turn off the beep. Only for Carvera Air.
    ///
    /// Example: M862
    case beepOff
}


// MARK: - ATC Status

enum ATCStatus: Int {

    /// No automatic tool-change operation.
    case none = 0

    /// Drop tool.
    case dropTool = 1

    /// Pick tool.
    case pickTool = 2

    /// Calibrate.
    case calibrate = 3

    /// Margin.
    case margin = 4

    /// Z probe.
    case zProbe = 5

    /// Autolevel.
    case autoLevel = 6

    /// Done.
    case done = 7
}
