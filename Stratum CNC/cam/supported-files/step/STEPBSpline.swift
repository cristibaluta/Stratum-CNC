import Foundation
import simd

/// Closest point on a segment, shared by polyline projection and flatness probes.
enum STEPSegment {
    static func closest(to point: SIMD3<Double>, _ a: SIMD3<Double>, _ b: SIMD3<Double>) -> (u: Double, distance: Double) {
        let ab = b - a
        let length2 = simd_length_squared(ab)
        let u = length2 > 0 ? min(1, max(0, simd_dot(point - a, ab) / length2)) : 0
        return (u, simd_distance(point, a + ab * u))
    }
}

/// Non-uniform, optionally rational B-spline in millimetres. Control points, knots and
/// weights come straight from the file; only `STEPBSpline.init` decides they are usable.
struct STEPBSpline {
    static let maximumDegree = 25
    static let maximumControlPoints = 500_000

    let degree: Int
    let controlPoints: [SIMD3<Double>]
    let weights: [Double]?
    /// Expanded knot vector: `controlPoints.count + degree + 1` entries.
    let knots: [Double]

    init(degree: Int, controlPoints: [SIMD3<Double>], weights: [Double]?,
         multiplicities: [Int], knotValues: [Double]) throws {
        guard (1...Self.maximumDegree).contains(degree) else {
            throw STEPParseError("Unsupported B-spline degree \(degree)")
        }
        let count = controlPoints.count
        guard count >= degree + 1, count <= Self.maximumControlPoints else {
            throw STEPParseError("B-spline of degree \(degree) needs \(degree + 1)...\(Self.maximumControlPoints) control points, found \(count)")
        }
        guard controlPoints.allSatisfy({ point in (0..<3).allSatisfy { point[$0].isFinite } }) else {
            throw STEPParseError("Nonfinite B-spline control point")
        }
        guard multiplicities.count == knotValues.count, knotValues.count >= 2 else {
            throw STEPParseError("B-spline knot and multiplicity lists disagree")
        }
        var expanded: [Double] = []
        expanded.reserveCapacity(count + degree + 1)
        for (index, value) in knotValues.enumerated() {
            guard value.isFinite, index == 0 || value > knotValues[index - 1] else {
                throw STEPParseError("B-spline knots must be finite and strictly increasing")
            }
            let isEnd = index == 0 || index == knotValues.count - 1
            // An interior knot of multiplicity degree + 1 would cut the curve in two.
            guard multiplicities[index] >= 1, multiplicities[index] <= (isEnd ? degree + 1 : degree) else {
                throw STEPParseError("Invalid B-spline knot multiplicity \(multiplicities[index]) at knot \(index)")
            }
            expanded.append(contentsOf: repeatElement(value, count: multiplicities[index]))
            guard expanded.count <= count + degree + 1 else {
                throw STEPParseError("B-spline knot multiplicities exceed \(count + degree + 1)")
            }
        }
        guard expanded.count == count + degree + 1 else {
            throw STEPParseError("B-spline needs \(count + degree + 1) knots for \(count) control points of degree \(degree), found \(expanded.count)")
        }
        if let weights {
            guard weights.count == count, weights.allSatisfy({ $0.isFinite && $0 > 0 }) else {
                throw STEPParseError("B-spline weights must be positive and match the control points")
            }
        }
        guard expanded[degree] < expanded[count] else { throw STEPParseError("B-spline has an empty parameter domain") }
        self.degree = degree
        self.controlPoints = controlPoints
        self.weights = weights
        knots = expanded
    }

    var domain: ClosedRange<Double> { knots[degree]...knots[controlPoints.count] }

    /// Distinct knot values strictly inside the domain, ascending.
    func interiorBreakpoints() -> [Double] {
        let range = domain
        var result: [Double] = []
        for value in knots[degree...controlPoints.count] where value > range.lowerBound && value < range.upperBound {
            if result.last != value { result.append(value) }
        }
        return result
    }

    /// Index k of the span [knots[k], knots[k+1]) holding `t`, never a zero-length one.
    private func span(for t: Double) -> Int {
        var low = degree
        var high = controlPoints.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if knots[middle] <= t { low = middle } else { high = middle - 1 }
        }
        while low > degree && knots[low] == knots[low + 1] { low -= 1 }
        return low
    }

    /// de Boor in homogeneous coordinates, so rational curves need no separate path.
    func point(at parameter: Double) -> SIMD3<Double> {
        let range = domain
        let t = min(max(parameter, range.lowerBound), range.upperBound)
        let k = span(for: t)
        var d: [SIMD4<Double>] = (0...degree).map { j in
            let index = j + k - degree
            let w = weights?[index] ?? 1
            let p = controlPoints[index]
            return SIMD4(p.x * w, p.y * w, p.z * w, w)
        }
        if degree >= 1 {
            for r in 1...degree {
                for j in stride(from: degree, through: r, by: -1) {
                    let i = j + k - degree
                    let denominator = knots[i + degree + 1 - r] - knots[i]
                    let alpha = denominator == 0 ? 0 : (t - knots[i]) / denominator
                    d[j] = (1 - alpha) * d[j - 1] + alpha * d[j]
                }
            }
        }
        let h = d[degree]
        return SIMD3(h.x, h.y, h.z) / h.w
    }

    // MARK: Sampling

    /// Adaptive polyline of the ascending interval [from, to].
    ///
    /// Every knot span first starts as `degree` pieces (at least 2), so no piece holds a whole
    /// S-bend that midpoint flatness would accept; refinement is then judged by probes.
    func sample(from a: Double, to b: Double, tolerance: Double, pointBudget: Int) -> STEPAdaptiveSampler.Sampling {
        var breaks = [a]
        breaks.append(contentsOf: interiorBreakpoints().filter { $0 > a && $0 < b })
        breaks.append(b)
        let parts = max(2, degree)
        var base: [Double] = []
        for (lo, hi) in zip(breaks, breaks.dropFirst()) {
            for i in 0..<parts { base.append(lo + (hi - lo) * Double(i) / Double(parts)) }
        }
        base.append(b)
        return STEPAdaptiveSampler.sample(parameters: base, tolerance: tolerance, pointBudget: pointBudget) { point(at: $0) }
    }
}

/// Finds the parameter of the curve point nearest a target: a coarse table over every knot
/// span, then golden-section refinement around the best sample. Build once per edge.
struct STEPBSplineProjector {
    private let spline: STEPBSpline
    private let samples: [(t: Double, point: SIMD3<Double>)]

    init(_ spline: STEPBSpline) {
        self.spline = spline
        let range = spline.domain
        var breaks = [range.lowerBound]
        breaks.append(contentsOf: spline.interiorBreakpoints())
        breaks.append(range.upperBound)
        let perSpan = max(2, min(32, 4096 / max(1, breaks.count - 1)))
        var table: [(t: Double, point: SIMD3<Double>)] = []
        for (lo, hi) in zip(breaks, breaks.dropFirst()) {
            for i in 0..<perSpan {
                let t = lo + (hi - lo) * Double(i) / Double(perSpan)
                table.append((t, spline.point(at: t)))
            }
        }
        table.append((range.upperBound, spline.point(at: range.upperBound)))
        samples = table
    }

    func closest(to target: SIMD3<Double>) -> (t: Double, distance: Double) {
        var best = 0
        var bestSquared = Double.infinity
        for (index, sample) in samples.enumerated() {
            let squared = simd_distance_squared(sample.point, target)
            if squared < bestSquared { best = index; bestSquared = squared }
        }
        func squaredDistance(_ t: Double) -> Double { simd_distance_squared(spline.point(at: t), target) }

        var a = samples[max(best - 1, 0)].t
        var b = samples[min(best + 1, samples.count - 1)].t
        let ratio = (5.0.squareRoot() - 1) / 2
        var c = b - ratio * (b - a)
        var d = a + ratio * (b - a)
        var fc = squaredDistance(c)
        var fd = squaredDistance(d)
        for _ in 0..<60 {
            if fc < fd {
                b = d; d = c; fd = fc
                c = b - ratio * (b - a); fc = squaredDistance(c)
            } else {
                a = c; c = d; fc = fd
                d = a + ratio * (b - a); fd = squaredDistance(d)
            }
        }
        let refined = (a + b) / 2
        let refinedSquared = squaredDistance(refined)
        return refinedSquared < bestSquared ? (refined, refinedSquared.squareRoot())
                                            : (samples[best].t, bestSquared.squareRoot())
    }
}
