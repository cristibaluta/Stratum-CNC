import Foundation

/// Part 21 values. Enumeration spelling is retained (including T/F/U).
indirect enum STEPValue: Equatable, Sendable {
    case integer(Int), real(Double), string(String), reference(Int), enumeration(String)
    case list([STEPValue]), typed(String, [STEPValue]), unset, derived

    var reference: Int? { if case .reference(let id) = self { return id }; return nil }
    var list: [STEPValue]? { if case .list(let values) = self { return values }; return nil }
    var enumeration: String? { if case .enumeration(let name) = self { return name }; return nil }
    var number: Double? {
        switch self {
            case .integer(let value): return Double(value)
            case .real(let value): return value
            case .typed(_, let values) where values.count == 1: return values[0].number
            default: return nil
        }
    }
}

struct STEPComponent: Sendable {
    let type: String
    let parameters: [STEPValue]
}

struct STEPParseError: Error, CustomStringConvertible, Sendable {
    let description: String
    init(_ description: String) { self.description = description }
}

struct STEPDiagnostic: Sendable {
    let entityID: Int?
    let message: String
}

/// No assembly instances yet: a representation/body pair identifies one occurrence.
struct STEPBodyID: Hashable, Sendable {
    let representationID: Int
    let entityID: Int
}

struct STEPEdgeID: Hashable, Sendable {
    let importID: UUID
    let bodyID: STEPBodyID
    let entityID: Int
}

struct STEPBodyInfo: Sendable {
    let id: STEPBodyID
    let contextID: Int
    let unitScaleToMM: Double
    let unitsAssumed: Bool
}

struct STEPEdge: Sendable {
    enum CurveKind: Sendable {
        case line
        /// Partial circular arc, sampled to a polyline.
        case arc
        /// Full closed circle, sampled to a polyline.
        case circle
        case ellipse
        case ellipticalArc
        /// A file polyline, cut to the edge's extent.
        case polyline
        case bspline
    }
    let id: STEPEdgeID
    let kind: CurveKind
    let points: [SIMD3<Double>]
    let startVertexID: Int
    let endVertexID: Int
    let adjacentFaceIDs: [Int]
    /// Distance (mm) between the sampled polyline and the true curve: a bound for lines,
    /// circles and ellipses, a probed estimate for B-splines. 0 for lines and file polylines.
    var chordError: Double = 0
}

struct STEPBounds: Sendable {
    var min: SIMD3<Double>
    var max: SIMD3<Double>

    mutating func include(_ point: SIMD3<Double>) {
        for axis in 0..<3 {
            min[axis] = Swift.min(min[axis], point[axis])
            max[axis] = Swift.max(max[axis], point[axis])
        }
    }
}

struct STEPEdgeModel: Sendable {
    let importID: UUID
    var edges: [STEPEdge] = []
    var bodies: [STEPBodyInfo] = []
    var bounds: STEPBounds?
    var diagnostics: [STEPDiagnostic] = []
    var indexedEntityCount = 0
    var reachableEdgeCount = 0
    var skippedEdgeCount: Int { reachableEdgeCount - edges.count }
}

struct STEPImportOptions: Sendable {
    /// Explicit opt-in only; unresolved units otherwise fail the import.
    var assumedUnitScaleToMM: Double? = nil
    /// Maximum sagitta (mm) of sampled circular edges. Display geometry only:
    /// a sampled polyline is not a machining contour.
    var chordToleranceMM: Double = 0.01
}
