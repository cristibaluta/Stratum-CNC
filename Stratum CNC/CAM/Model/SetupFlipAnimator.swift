//
//  SetupFlipAnimator.swift
//  Stratum CNC
//
import SwiftUI
import simd

extension SetupFrame {

    /// The point the stock turns about: the middle of its thickness, centred across the axis.
    /// (Its position along the axis itself doesn't matter for a turn about that axis.)
    fileprivate var turnCenter: SIMD3<Float> {
        switch axis {
            case .x: return SIMD3<Float>(0, Float(pivot), Float(axisZ))
            case .y: return SIMD3<Float>(Float(pivot), 0, Float(axisZ))
        }
    }

    /// The part's matrix part-way (`t` in 0…1) from one setup's face to another's: the stock
    /// *flips over* instead of snapping. The rotation is slerped between the two orientations, and the
    /// stock's centre travels from where it is in the first setup to where it is in the second,
    /// lifted over the work bed on the way so the turn doesn't dip through it. Exactly
    /// `from.matrix` at 0 and `to.matrix` at 1.
    static func flipMatrix(from: SetupFrame, to: SetupFrame, t: Float) -> simd_float4x4 {
        if t <= 0 { return from.matrix }
        if t >= 1 { return to.matrix }

        let fromMatrix = from.matrix
        let toMatrix = to.matrix
        let center = to.isIdentity ? from.turnCenter : to.turnCenter

        func rotation(_ m: simd_float4x4) -> simd_float3x3 {
            simd_float3x3(SIMD3<Float>(m.columns.0.x, m.columns.0.y, m.columns.0.z),
                          SIMD3<Float>(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                          SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z))
        }
        func point(_ m: simd_float4x4) -> SIMD3<Float> {
            let p = m * SIMD4<Float>(center.x, center.y, center.z, 1)
            return SIMD3<Float>(p.x, p.y, p.z)
        }

        let orientation = simd_slerp(simd_quatf(rotation(fromMatrix)), simd_quatf(rotation(toMatrix)), t)
        var result = simd_float4x4(orientation)

        var position = simd_mix(point(fromMatrix), point(toMatrix), SIMD3<Float>(repeating: t))
        let lift = Float(max(from.pivot, to.pivot, from.surfaceDistance, to.surfaceDistance)) * 0.75
        position.z += lift * sin(.pi * t)

        // result * p = R (p - center) + position
        let turned = result * SIMD4<Float>(center.x, center.y, center.z, 0)
        result.columns.3 = SIMD4<Float>(position.x - turned.x, position.y - turned.y, position.z - turned.z, 1)
        return result
    }
}

/// Drives the flip between two setups' faces: while it runs, the canvas draws the part (stock and
/// model together) with `displayMatrix(for:)` instead of the target frame's own matrix.
@MainActor
final class SetupFlipAnimator: ObservableObject {

    /// 0…1 linear time; the easing is applied when the matrix is made.
    @Published private(set) var progress: Float = 1

    private var from: SetupFrame
    private var to: SetupFrame
    private var startDate = Date()
    private var timer: Timer?

    let duration: TimeInterval = 0.75

    init(initial: SetupFrame) {
        from = initial
        to = initial
    }

//    deinit {
//        timer?.invalidate()
//    }

    /// True from the moment the view is handed a new frame until the flip has finished, including
    /// the render before `start(to:)` has been called.
    func isFlipping(to target: SetupFrame) -> Bool {
        target != to || progress < 1
    }

    /// The matrix to draw the part with now, for the frame the view is showing.
    func displayMatrix(for target: SetupFrame) -> simd_float4x4 {
        if target != to {
            // The change hasn't started its animation yet: keep showing where it is
            return SetupFrame.flipMatrix(from: from, to: to, t: Self.eased(progress))
        }
        return progress < 1 ? SetupFrame.flipMatrix(from: from, to: to, t: Self.eased(progress)) : target.matrix
    }

    func start(to target: SetupFrame) {
        guard target != to else {
            return
        }
        // A new face picked mid-flip carries on from the one it was heading to
        from = to
        to = target
        progress = 0
        startDate = Date()
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let elapsed = Date().timeIntervalSince(startDate)
        let value = Float(min(1, elapsed / duration))
        progress = value
        if value >= 1 {
            timer?.invalidate()
            timer = nil
        }
    }

    private static func eased(_ t: Float) -> Float {
        t * t * (3 - 2 * t)
    }
}
