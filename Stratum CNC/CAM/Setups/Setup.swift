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

import Foundation

struct Setup: Identifiable, Codable, Hashable, Sendable {

    var id = UUID()
    var name: String
    /// Rotation of the stock about `axis`, degrees, in 0..<360.
    var angle: Double
    /// The machine axis the stock turns about.
    var axis: SetupAxis

    init(id: UUID = UUID(), name: String, angle: Double, axis: SetupAxis = .x) {
        self.id = id
        self.name = name
        self.angle = Self.normalized(angle)
        self.axis = axis
    }

    init(face: SetupFace, axis: SetupAxis? = nil, name: String? = nil) {
        let axis = face.hasChoiceOfAxis ? (axis ?? face.axis) : face.axis
        self.init(name: name ?? Self.baseName(for: face, axis: axis), angle: face.angle, axis: axis)
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
