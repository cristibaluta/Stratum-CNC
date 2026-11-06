import Foundation
import simd

/// Analytic surface descriptors retained next to the triangle mesh. Steps 7 and 8
/// (face picking, feature recognition) need exact radii, axes and normals, not just
/// triangles. All lengths are millimetres, angles radians, in source coordinates.
///
/// Every surface is parametrised so that `∂P/∂u × ∂P/∂v` is the STEP surface normal.
/// That makes triangles that run counter-clockwise in (u, v) face along the surface
/// normal, and the tessellator only has to flip them for a face with `same_sense = .F`.
enum STEPSurface: Sendable {
    case plane(STEPFrame)
    /// Radius about the frame's Z axis; v is the distance along that axis.
    case cylinder(STEPFrame, radius: Double)
    /// Radius at v = 0 and half-angle, so the radius at v is `radius + v·tan(halfAngle)`.
    case cone(STEPFrame, radius: Double, halfAngle: Double)
    /// u is longitude, v latitude in [-π/2, π/2].
    case sphere(STEPFrame, radius: Double)
    /// u runs round the main axis, v round the tube.
    case torus(STEPFrame, major: Double, minor: Double)

    struct Parameters {
        var u: Double
        var v: Double
        /// u is meaningless here: on the sphere's poles or at a cone's apex.
        var isPole: Bool
    }

    var frame: STEPFrame {
        switch self {
            case .plane(let frame): return frame
            case .cylinder(let frame, _): return frame
            case .cone(let frame, _, _): return frame
            case .sphere(let frame, _): return frame
            case .torus(let frame, _, _): return frame
        }
    }

    var kindName: String {
        switch self {
            case .plane: return "plane"
            case .cylinder: return "cylinder"
            case .cone: return "cone"
            case .sphere: return "sphere"
            case .torus: return "torus"
        }
    }

    /// True when u wraps every 2π.
    var isPeriodicU: Bool {
        if case .plane = self { return false }
        return true
    }

    /// True when v also wraps every 2π (only the torus).
    var isPeriodicV: Bool {
        if case .torus = self { return true }
        return false
    }

    func point(u: Double, v: Double) -> SIMD3<Double> {
        let f = frame
        let radial = cos(u) * f.x + sin(u) * f.y
        switch self {
            case .plane:
                return f.origin + u * f.x + v * f.y
            case .cylinder(_, let radius):
                return f.origin + radius * radial + v * f.z
            case .cone(_, let radius, let halfAngle):
                return f.origin + (radius + v * tan(halfAngle)) * radial + v * f.z
            case .sphere(_, let radius):
                return f.origin + radius * (cos(v) * radial + sin(v) * f.z)
            case .torus(_, let major, let minor):
                return f.origin + (major + minor * cos(v)) * radial + minor * sin(v) * f.z
        }
    }

    /// Unit normal along the STEP surface normal (before any face `same_sense`).
    func normal(u: Double, v: Double) -> SIMD3<Double> {
        let f = frame
        let radial = cos(u) * f.x + sin(u) * f.y
        switch self {
            case .plane:
                return f.z
            case .cylinder:
                return radial
            case .cone(_, _, let halfAngle):
                let slope = tan(halfAngle)
                return (radial - slope * f.z) / (1 + slope * slope).squareRoot()
            case .sphere, .torus:
                return cos(v) * radial + sin(v) * f.z
        }
    }

    /// Inverse of `point`, for points on (or very near) the surface.
    func parameters(of point: SIMD3<Double>) -> Parameters {
        let f = frame
        let offset = point - f.origin
        let x = simd_dot(offset, f.x)
        let y = simd_dot(offset, f.y)
        let z = simd_dot(offset, f.z)
        let radial = (x * x + y * y).squareRoot()
        let u = atan2(y, x)
        switch self {
            case .plane:
                return Parameters(u: x, v: y, isPole: false)
            case .cylinder(_, let radius):
                return Parameters(u: u, v: z, isPole: radial < 1e-9 * max(1, radius))
            case .cone(_, let radius, _):
                return Parameters(u: u, v: z, isPole: radial < 1e-9 * max(1, radius, abs(z)))
            case .sphere(_, let radius):
                return Parameters(u: u, v: atan2(z, radial), isPole: radial < 1e-9 * max(1, radius))
            case .torus(_, let major, _):
                return Parameters(u: u, v: atan2(z, radial - major), isPole: false)
        }
    }

    /// Radius of the widest circle of constant v over `vRange`; it sets how finely u must be
    /// subdivided. `nil` for the plane.
    func widestRadius(vRange: ClosedRange<Double>) -> Double? {
        switch self {
            case .plane: return nil
            case .cylinder(_, let radius): return radius
            case .cone(_, let radius, let halfAngle):
                let slope = tan(halfAngle)
                return max(abs(radius + vRange.lowerBound * slope), abs(radius + vRange.upperBound * slope))
            case .sphere(_, let radius): return radius
            case .torus(_, let major, let minor): return major + minor
        }
    }

    /// Radius of curvature along v where the surface is not ruled in v (sphere, torus tube).
    /// `nil` where straight lines in v lie on the surface (plane, cylinder, cone).
    var radiusAlongV: Double? {
        switch self {
            case .plane, .cylinder, .cone: return nil
            case .sphere(_, let radius): return radius
            case .torus(_, _, let minor): return minor
        }
    }
}
