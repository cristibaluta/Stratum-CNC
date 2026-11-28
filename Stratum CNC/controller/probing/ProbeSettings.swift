//
//  ProbeSettings.swift
//  Stratum CNC
//
//  What the person tunes once and rarely touches again: heights, feeds,
//  distances and the probe's ball. Persisted like `levelBeforeRun`.
//  All distances are millimeters, all feeds mm/min.
//

import Foundation

/// The probing tools. The metal and ruby probes are touched the same way; the
/// difference is what they can touch. The laser touches nothing: the person
/// focuses it on the surface, and it only finds a height (Z).
enum ProbeHardware: String, CaseIterable, Identifiable, Codable {
    /// Detects contact through the stock, so the stock has to be metal.
    case metal
    /// A ruby ball: works on any stock.
    case ruby
    /// The laser module's beam, focused by eye on the surface. No contact, so
    /// any stock works, but it can only set Z.
    case laser

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
            case .metal: "Metal Probe"
            case .ruby: "Ruby Probe"
            case .laser: "Laser Probe"
        }
    }

    /// Touches the stock (and so has a ball and a trigger to check).
    var isContact: Bool {
        self != .laser
    }

    /// The tools that can be offered for `kind`. The laser only finds a height.
    static func options(for kind: ProbeKind) -> [ProbeHardware] {
        kind == .zSurface ? allCases : allCases.filter { $0 != .laser }
    }

    var detail: String {
        switch self {
            case .metal: "Metallic stock only"
            case .ruby: "Any stock"
            case .laser: "Z only, no contact"
        }
    }

    var explanation: String {
        switch self {
            case .metal: "The metal probe only works on metallic stock. For wood, plastic or other materials use the ruby probe."
            case .ruby: "The ruby probe works on any stock: metal, wood, plastic and composites."
            case .laser: "The laser probe does not touch the stock, so it works on anything. You turn the laser on at low power, jog until the dot is sharp on the surface, and Z0 is set there. It only finds Z."
        }
    }
}

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

    /// Which of the two probes is used. Nil until chosen (the ruby is
    /// assumed, as it works on everything).
    var hardware: ProbeHardware?
    var ballDiameter = 2.0
    /// Set once the person has confirmed the ball diameter, so the dialog
    /// asks the first time instead of trusting the default.
    var hasConfirmedBallDiameter = false
    /// Probe tip versus tool tip, if the machine does not already apply it.
    var zOffset = 0.0
    /// Tool number of the probe in the tool changer (the Carvera's is T0).
    var probeTool = 0
    /// Laser probe only: the height of the laser's focus above the surface it
    /// is focused on (0 when the dot is sharp exactly on it). Written as Z.
    /// Optional so settings saved before the laser existed still decode.
    private var storedLaserZOffset: Double?
    var laserZOffset: Double {
        get { storedLaserZOffset ?? 0 }
        set { storedLaserZOffset = newValue }
    }

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

    var ballRadius: Double {
        ballDiameter / 2
    }

    /// The probe in use.
    var probe: ProbeHardware {
        hardware ?? .ruby
    }

    /// The tool that will really be used for `kind`: the laser is only for Z,
    /// so for XY a laser choice falls back to the ruby.
    func probe(for kind: ProbeKind) -> ProbeHardware {
        let chosen = probe
        return ProbeHardware.options(for: kind).contains(chosen) ? chosen : .ruby
    }

    /// "G54" … "G59".
    var workCoordinateSystemName: String {
        "G\(53 + workCoordinateSystem)"
    }

    /// The depth a side touch actually uses: the setting, but always leaving
    /// at least 1 mm of the stock above the ball's lowest point so it never
    /// goes under the stock.
    func edgeDepth(forStockThickness thickness: Double) -> Double {
        min(edgeDepth, max(0.5, thickness - 1))
    }

    /// Reasons the settings can't be used for a run. Empty when fine.
    var problems: [String] {
        generalProblems + contactProblems
    }

    /// The problems that matter for every tool, the laser included.
    var generalProblems: [String] {
        var result: [String] = []
        if !(1...6).contains(workCoordinateSystem) {
            result.append("The work coordinate system must be G54 to G59.")
        }
        if safeZ <= 0 {
            result.append("The safe Z must be above 0.")
        }
        return result
    }

    /// The problems that only matter when a probe touches the stock.
    var contactProblems: [String] {
        var result: [String] = []
        if ballDiameter <= 0 {
            result.append("The probe ball diameter must be above 0.")
        }
        if searchFeed <= 0 || measureFeed <= 0 {
            result.append("The feeds must be above 0.")
        }
        if measureFeed > searchFeed {
            result.append("The measure feed should not be faster than the search feed.")
        }
        if searchDistance <= retractDistance {
            result.append("The search distance must be longer than the retract distance.")
        }
        return result
    }

    // MARK: Persistence

    static let defaultsKey = "probeSettings"

    static func load(from defaults: UserDefaults = .standard) -> ProbeSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(ProbeSettings.self, from: data)
        else {
            return ProbeSettings()
        }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else {
            return
        }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
