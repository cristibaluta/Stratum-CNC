//
//  ObjectTransform.swift
//  Stratum CNC
//
//  Where an object sits in the project, in one value type. A 2D shape (DXF, SVG, Gerber) and a
//  STEP body both have one, so a setup can later hold "this object, placed like this" without
//  caring which kind it is.
//
//  This is the project's global placement. A setup will be able to carry its own override
//  (`SetupItem.transformOverride`, step 2); with no override the global one is used.
//
//      x, y      bottom-left corner of the object (STEP: its corner, min X / min Y), mm
//      z         STEP only: where the body's top sits. 0 for a 2D shape
//      scale     uniform, 1 = as imported
//      rotation  degrees about the object's centre, 0..<360. 2D shapes only (a STEP body is
//                turned by `face`, not by an angle)
//      face      STEP only: which face of the model faces up. `.top` for a 2D shape
//

import Foundation

struct ObjectTransform: Codable, Hashable, Sendable {

    var x: Double = 0
    var y: Double = 0
    var z: Double = 0
    var scale: Double = 1
    var rotation: Double = 0
    var face: SetupFace = .top

    static let identity = ObjectTransform()
}

extension D2_Object {

    /// The object's placement as one value. Reading it changes nothing; writing it is the same as
    /// setting `position`, `width` and the rotation one by one. A parametric object (the alignment
    /// pins) is placed by its parameters and the stock, so writing to it does nothing.
    var transform: ObjectTransform {
        get {
            ObjectTransform(x: Double(position.x),
                            y: Double(position.y),
                            z: 0,
                            scale: Double(scale),
                            rotation: Double(rotationDegrees),
                            face: .top)
        }
        set {
            guard !isParametric else {
                return
            }
            position = CGPoint(x: newValue.x, y: newValue.y)
            width = max(CGFloat(newValue.scale) * originalSize.width, 0.001)
            setRotation(CGFloat(newValue.rotation))
        }
    }
}
