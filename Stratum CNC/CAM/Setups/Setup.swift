//
//  Setup.swift
//  Stratum CNC
//
//  A setup is one way the stock is held on the machine. Its orientation is a rotation of the
//  stock by an angle, in degrees, about a horizontal machine axis through the stock's centre
//  (X or Y). Today the angle is one of four quarter turns; a rotary axis later means any angle,
//  without changing anything stored.
//
//      face     axis  angle   up direction in the part's frame
//      top      -     0       +Z
//      front    X     90      −Y   (the face toward the operator; machine Y+ is the back)
//      bottom   X|Y   180     −Z   (flipped over about X: shapes mirror in Y; about Y: in X)
//      back     X     270     +Y
//      left     Y     90      −X
//      right    Y     270     +X
//
//  Toolpaths are generated in the setup's own frame (`SetupFrame`): the part is rotated by
//  −angle about the axis through the stock's centre, and z0 is the stock's surface that is now
//  facing up. Every Z field of a toolpath therefore keeps meaning "depth below this setup's z0".
//  A side face stands the stock on its edge, so its footprint is another size: it is slid back
//  to the origin, with its corner at X = 0, Y = 0, like the top's.
//
//  Stock: the project keeps a list of stocks (`ProjectStock`) and a setup points at one of them
//  (`stockID`); several setups can use the same one. That is how one part is milled in two
//  materials: a face in one workpiece, and some edges in another, each with its own z0, program
//  and stock change in between. A new setup starts on the active one's stock.
//
//  Fixtures: they are attached to the stock (`ProjectStock.fixtures`), so every setup on that stock
//  can use them. `usesFixtures` is the setup's checkbox: whether the fixtures are in this setup.
//

import Foundation

extension StockMaterial {

    /// The stock of a new project, and of a setup saved without one.
    static let defaultWorkpiece = StockMaterial(
        name: "Workpiece",
        material: .aluminum,
        geometry: .rectangular(width: 100, height: 100, depth: 10)
    )
}

// `@unchecked Sendable` and the hand-written `hash(into:)`: `StockMaterial` isn't declared Hashable or
// Sendable, but it is a plain value (enums and numbers). Equality is still the synthesized one,
// over every field, and hashing the id alone is consistent with it.
struct Setup: Identifiable, Codable, Hashable, @unchecked Sendable {

    var id = UUID()
    var name: String
    /// Rotation of the stock about `axis`, degrees, in 0..<360.
    var angle: Double
    /// The machine axis the stock turns about.
    var axis: SetupAxis
    /// The workpiece this setup is cut from: an entry of the project's stocks.
    var stockID: UUID
    /// Whether the fixtures of the stock (the alignment pins) are part of this setup: drawn on its
    /// canvas and available to cut.
    var usesFixtures: Bool = false
    /// Only for a project saved when each setup carried its own stock: what it read. `ProjectStocks.migrate`
    /// moves it into the project's list and clears it. Never saved.
    var legacyStock: StockMaterial?
    /// The objects this setup includes, each with an optional placement of its own (see `SetupItem`).
    /// Empty (the default) includes every object of the project.
    var items: [SetupItem] = []

    private enum CodingKeys: String, CodingKey {
        case id, name, angle, axis, stockID, usesFixtures, items
    }

    /// The key of the stock a setup used to carry; only read.
    private enum LegacyKeys: String, CodingKey {
        case stock
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        angle = try c.decode(Double.self, forKey: .angle)
        axis = try c.decode(SetupAxis.self, forKey: .axis)
        usesFixtures = try c.decodeIfPresent(Bool.self, forKey: .usesFixtures) ?? false
        items = try c.decodeIfPresent([SetupItem].self, forKey: .items) ?? []

        if let saved = try c.decodeIfPresent(UUID.self, forKey: .stockID) {
            stockID = saved
        } else {
            // Saved with a stock of its own (or none): it moves into the project's list on open
            stockID = UUID()
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            legacyStock = try legacy.decodeIfPresent(StockMaterial.self, forKey: .stock) ?? .defaultWorkpiece
        }
    }

    init(id: UUID = UUID(), name: String, angle: Double, axis: SetupAxis = .x, stockID: UUID, usesFixtures: Bool = false) {
        self.id = id
        self.name = name
        self.angle = Self.normalized(angle)
        self.axis = axis
        self.stockID = stockID
        self.usesFixtures = usesFixtures
    }

    init(face: SetupFace, axis: SetupAxis? = nil, name: String? = nil, stockID: UUID, usesFixtures: Bool = false) {
        let axis = face.hasChoiceOfAxis ? (axis ?? face.axis) : face.axis
        self.init(name: name ?? Self.baseName(for: face, axis: axis),
                  angle: face.angle,
                  axis: axis,
                  stockID: stockID,
                  usesFixtures: usesFixtures)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var orientation: SetupOrientation {
        SetupOrientation(angle: angle, axis: axis)
    }

    /// The face this setup looks at, nil for an angle between faces (a rotary index).
    var face: SetupFace? {
        SetupFace(angle: angle, axis: axis)
    }

    /// "Top", "Front"… ("Bottom (flip Y)" when flipped about Y) or "45°" for an angle that is not a face.
    var orientationTitle: String {
        face.map { Self.baseName(for: $0, axis: axis) }
            ?? "\(angle.formatted(.number.precision(.fractionLength(0...1))))°"
    }

    /// The default name of a face: its title, with the flip axis when that is not the usual X.
    static func baseName(for face: SetupFace, axis: SetupAxis) -> String {
        face.hasChoiceOfAxis && axis != face.axis ? "\(face.title) (flip \(axis.title))" : face.title
    }

    static func normalized(_ angle: Double) -> Double {
        let wrapped = angle.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// A name for a new setup that isn't taken yet: "Front", then "Front 2", "Front 3"…
    static func uniqueName(for face: SetupFace, axis: SetupAxis? = nil, among taken: Set<String>) -> String {
        let base = baseName(for: face, axis: axis ?? face.axis)
        guard taken.contains(base) else {
            return base
        }
        var n = 2
        while taken.contains("\(base) \(n)") {
            n += 1
        }
        return "\(base) \(n)"
    }
}
