//
//  ProbeSettings.swift
//  Stratum CNC
//
//  What the person tunes once and rarely touches again: heights, feeds,
//  distances and the probe's ball. Persisted like `levelBeforeRun`.
//  All distances are millimeters, all feeds mm/min.
//

import Foundation

struct ProbeSettings: Codable, Equatable {

    // MARK: Travel

    /// Clearance above the stock top used for every travel move between touches.
    var safeZ = 10.0
    /// Park the probe at `parkX`/`parkY` (machine coordinates) when finished.
    var usesParkPosition = false
    var parkX = 0.0
    var parkY = 0.0

    // MARK: Touching

    /// First, fast touch.
    var searchFeed = 100.0
    /// Second, slow touch that gives the measurement.
    var measureFeed = 15.0
    /// Back-off between the two touches.
    var retractDistance = 1.5
    /// Longest probe move. A probe that has not touched after this far stops.
    var searchDistance = 20.0
    /// Fast touch, back off, slow touch. Off is quicker and less accurate.
    var usesTwoPass = true

    // MARK: Probe

    var ballDiameter = 2.0
    /// Set once the person has confirmed the ball diameter, so the dialog
    /// asks the first time instead of trusting the default.
    var hasConfirmedBallDiameter = false
    /// Probe tip versus tool tip, if the machine does not already apply it.
    var zOffset = 0.0
    /// Tool number of the probe in the tool changer (the Carvera's is T0).
    var probeTool = 0

    // MARK: Cycle

    /// How far below the stock top a side is touched.
    var edgeDepth = 3.0
    /// How far past the expected edge a side touch starts.
    var outsideClearance = 5.0
    /// Distance of the "jog here" dot from the corner.
    var startInset = 10.0
    /// Work coordinate system the result is written to: 1 = G54 … 6 = G59.
    var workCoordinateSystem = 1
    var setsZ = true
    /// Circles: touch four sides, move to the center found, and touch again.
    var refinesCircle = true

    // MARK: Derived

    var ballRadius: Double { ballDiameter / 2 }

    /// "G54" … "G59".
    var workCoordinateSystemName: String { "G\(53 + workCoordinateSystem)" }

    /// The depth a side touch actually uses: the setting, but always leaving
    /// at least 1 mm of the stock above the ball's lowest point so it never
    /// goes under the stock.
    func edgeDepth(forStockThickness thickness: Double) -> Double {
        min(edgeDepth, max(0.5, thickness - 1))
    }

    /// Reasons the settings can't be used for a run. Empty when fine.
    var problems: [String] {
        var result: [String] = []
        if ballDiameter <= 0 { result.append("The probe ball diameter must be above 0.") }
        if safeZ <= 0 { result.append("The safe Z must be above 0.") }
        if searchFeed <= 0 || measureFeed <= 0 { result.append("The feeds must be above 0.") }
        if measureFeed > searchFeed { result.append("The measure feed should not be faster than the search feed.") }
        if searchDistance <= retractDistance { result.append("The search distance must be longer than the retract distance.") }
        if !(1...6).contains(workCoordinateSystem) { result.append("The work coordinate system must be G54 to G59.") }
        return result
    }

    // MARK: Persistence

    static let defaultsKey = "probeSettings"

    static func load(from defaults: UserDefaults = .standard) -> ProbeSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(ProbeSettings.self, from: data)
        else { return ProbeSettings() }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
