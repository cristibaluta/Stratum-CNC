import Testing
import Foundation
@testable import Stratum_CNC

struct ProbeCycleBuilderTests {

    // Defaults: safe Z 10, feeds 100/15, retract 1.5, search 20, ball Ø2 (r = 1),
    // side depth 3, clearance 5, dot 10 mm in from the edge.
    private let rectangle = StockGeometry.rectangular(width: 100, height: 60, depth: 10)
    private let disk = StockGeometry.disk(outerDiameter: 50, innerDiameter: 15, depth: 13)
    private let solidDisk = StockGeometry.disk(outerDiameter: 50, innerDiameter: 0, depth: 13)
    private let cylinder = StockGeometry.cylindrical(diameter: 20, length: 200)
    private let zero = "G10 L20 P1 Z0"

    private func steps(_ geometry: StockGeometry,
                       configure: (inout ProbeFlow) -> Void = { _ in },
                       settings: ProbeSettings = ProbeSettings()) -> [ProbeStepPlan] {
        var flow = ProbeFlow(geometry: geometry)
        configure(&flow)
        return ProbeCycleBuilder(flow: flow, settings: settings, zeroZCommand: zero).build()
    }

    private func lines(_ steps: [ProbeStepPlan], _ contacts: ProbeContacts = ProbeContacts()) -> [String] {
        steps.flatMap { $0.lines(contacts) }
    }

    private func step(_ title: String, in steps: [ProbeStepPlan]) throws -> ProbeStepPlan {
        try #require(steps.first { $0.title == title })
    }

    // MARK: Numbers

    @Test func numbersAreTrimmed() {
        #expect(ProbeCycleBuilder.number(10) == "10")
        #expect(ProbeCycleBuilder.number(1.5) == "1.5")
        #expect(ProbeCycleBuilder.number(-0.0004) == "0")
        #expect(ProbeCycleBuilder.number(-2.25) == "-2.25")
        #expect(ProbeCycleBuilder.number(100) == "100")
    }

    // MARK: Start and end

    @Test func startsRelativeAndEndsAbsolute() {
        let all = steps(rectangle)
        #expect(all.first?.title == "Prepare")
        #expect(all.first?.lines(ProbeContacts()) == ["G21", "G92.1", "G54", "G91"])
        #expect(all.last?.lines(ProbeContacts()) == ["G90"])
    }

    @Test func parksWhenAsked() {
        var settings = ProbeSettings()
        settings.usesParkPosition = true
        settings.parkX = -5
        settings.parkY = -7.5
        let all = steps(rectangle, settings: settings)
        #expect(all.last?.lines(ProbeContacts()) == ["G90", "G53 G0 X-5 Y-7.5"])
        #expect(all.last?.title == "Finish and park")
    }

    // MARK: Z

    @Test func zTouchIsFastBackOffSlowThenZeroThenLift() throws {
        let all = steps(rectangle) { $0.kind = .zSurface }
        let top = try step("Touch the top", in: all).lines(ProbeContacts())
        #expect(top == ["G38.2 Z-20 F100", "G0 Z1.5", "G38.2 Z-2.5 F15", zero, "G0 Z10"])
    }

    @Test func singleTouchWhenTwoPassIsOff() throws {
        var settings = ProbeSettings()
        settings.usesTwoPass = false
        let all = steps(rectangle, configure: { $0.kind = .zSurface }, settings: settings)
        let top = try step("Touch the top", in: all).lines(ProbeContacts())
        #expect(top == ["G38.2 Z-20 F100", zero, "G0 Z10"])
    }

    @Test func zOffsetUsesTheWorkOffsetCommand() throws {
        var settings = ProbeSettings()
        settings.zOffset = 1.5
        let all = steps(rectangle, configure: { $0.kind = .zSurface }, settings: settings)
        let top = try step("Touch the top", in: all).lines(ProbeContacts())
        #expect(top.contains("G10 L20 P1 Z1.5"))
        #expect(!top.contains(zero))
    }

    @Test func cornerCanLeaveZAlone() throws {
        var settings = ProbeSettings()
        settings.setsZ = false
        let all = steps(rectangle, settings: settings)
        let top = try step("Touch the top", in: all).lines(ProbeContacts())
        #expect(!top.contains(zero))
    }

    @Test func zOnlyAlwaysSetsZ() throws {
        var settings = ProbeSettings()
        settings.setsZ = false
        let all = steps(rectangle, configure: { $0.kind = .zSurface }, settings: settings)
        let top = try step("Touch the top", in: all).lines(ProbeContacts())
        #expect(top.contains(zero))
    }

    @Test func zOnlyHasNoSideMoves() {
        let all = lines(steps(rectangle) { $0.kind = .zSurface })
        #expect(!all.contains { $0.hasPrefix("G38.3") })
        #expect(!all.contains { $0.contains("X") && $0.hasPrefix("G38.2") })
    }

    @Test func zTouchChecksTheProbeWasNotAlreadyTriggered() throws {
        let top = try step("Touch the top", in: steps(rectangle) { $0.kind = .zSurface })

        var stuck = ProbeContacts()
        stuck[ProbeKey.start] = SIMD3(0, 0, -10)
        stuck[ProbeKey.zTop] = SIMD3(0, 0, -10)
        #expect(top.check?(stuck) != nil)

        var fine = ProbeContacts()
        fine[ProbeKey.start] = SIMD3(0, 0, -10)
        fine[ProbeKey.zTop] = SIMD3(0, 0, -35)
        #expect(top.check?(fine) == nil)
    }

    // MARK: Corner

    @Test func bottomLeftCornerTouchesLeftThenBottomFromOutside() throws {
        let all = steps(rectangle) { $0.corner = .bottomLeft }

        // Dot at (10, 10): the left side is 10 away, the probe moves +X.
        #expect(try step("Move outside the left side and lower", in: all).lines(ProbeContacts())
                == ["G0 X-15", "G38.3 Z-13 F100"])
        #expect(try step("Touch the left side", in: all).lines(ProbeContacts())
                == ["G38.2 X20 F100", "G0 X-1.5", "G38.2 X2.5 F15"])
        #expect(try step("Back above the stock", in: all).lines(ProbeContacts())
                == ["G0 Z13", "G0 X11"])

        #expect(try step("Move outside the bottom side and lower", in: all).lines(ProbeContacts())
                == ["G0 Y-15", "G38.3 Z-13 F100"])
        #expect(try step("Touch the bottom side", in: all).lines(ProbeContacts())
                == ["G38.2 Y20 F100", "G0 Y-1.5", "G38.2 Y2.5 F15"])
    }

    @Test func topRightCornerMirrorsTheSigns() throws {
        let all = steps(rectangle) { $0.corner = .topRight }

        #expect(try step("Move outside the right side and lower", in: all).lines(ProbeContacts())
                == ["G0 X15", "G38.3 Z-13 F100"])
        #expect(try step("Touch the right side", in: all).lines(ProbeContacts())
                == ["G38.2 X-20 F100", "G0 X1.5", "G38.2 X-2.5 F15"])
        #expect(try step("Back above the stock", in: all).lines(ProbeContacts())
                == ["G0 Z13", "G0 X-11"])
        #expect(try step("Touch the top side", in: all).lines(ProbeContacts())
                == ["G38.2 Y-20 F100", "G0 Y1.5", "G38.2 Y-2.5 F15"])
    }

    @Test func cornerTouchesExactlyTwoSides() {
        let all = steps(rectangle)
        #expect(all.filter { $0.title.hasPrefix("Touch the") && $0.title != "Touch the top" }.count == 2)
    }

    @Test func loweringBesideTheStockUsesTheQuietProbeAndIsChecked() throws {
        let all = steps(rectangle)
        let lower = try step("Move outside the left side and lower", in: all)
        #expect(lower.measure == ProbeKey.lowered(.x, 1))
        #expect(!lower.recovery.isEmpty)

        let key = ProbeKey.lowered(.x, 1)
        var good = ProbeContacts()
        good[ProbeKey.zTop] = SIMD3(0, 0, -50)
        good[key] = SIMD3(0, 0, -53)            // went the whole 3 mm below the top
        #expect(lower.check?(good) == nil)

        var touched = ProbeContacts()
        touched[ProbeKey.zTop] = SIMD3(0, 0, -50)
        touched[key] = SIMD3(0, 0, -45)         // stopped above the top: it hit the stock
        #expect(lower.check?(touched) != nil)
    }

    // MARK: Edge

    @Test func rightEdgeTouchesOnlyTheRightSide() {
        let all = steps(rectangle) {
            $0.kind = .edge
            $0.edge = .right
        }
        let sideTouches = all.filter { $0.title.hasPrefix("Touch the") && $0.title != "Touch the top" }
        #expect(sideTouches.map(\.title) == ["Touch the right side"])
    }

    @Test func sideDepthNeverGoesUnderThinStock() throws {
        let thin = StockGeometry.rectangular(width: 100, height: 60, depth: 3)
        let all = steps(thin)
        // 3 mm thick: depth is 2 mm, so the lowering is safe Z 10 + 2.
        #expect(try step("Move outside the left side and lower", in: all).lines(ProbeContacts()).last
                == "G38.3 Z-12 F100")
    }

    // MARK: Rectangle center

    @Test func rectangleCenterTouchesFourSidesFromTheMiddle() throws {
        let all = steps(rectangle) { $0.kind = .center }
        let titles = all.map(\.title)
        #expect(titles.contains("Touch the left side"))
        #expect(titles.contains("Touch the right side"))
        #expect(titles.contains("Touch the bottom side"))
        #expect(titles.contains("Touch the top side"))

        // The dot is in the middle: 50 from the left and right, 30 from the bottom and top.
        #expect(try step("Move outside the left side and lower", in: all).lines(ProbeContacts()).first == "G0 X-55")
        #expect(try step("Move outside the bottom side and lower", in: all).lines(ProbeContacts()).first == "G0 Y-35")
    }

    @Test func rectangleCenterMovesToTheMiddleOfTheTouches() throws {
        let all = steps(rectangle) { $0.kind = .center }
        let move = try step("Move to the center", in: all)

        // Preview, before anything was touched: nothing to compute yet.
        #expect(move.lines(ProbeContacts()).allSatisfy { $0.hasPrefix(";") })

        var contacts = ProbeContacts()
        contacts[ProbeKey.side(.x, 1)] = SIMD3(-120, -80, -50)
        contacts[ProbeKey.side(.x, -1)] = SIMD3(-20, -80, -50)
        contacts[ProbeKey.side(.y, 1)] = SIMD3(-70, -100, -50)
        contacts[ProbeKey.side(.y, -1)] = SIMD3(-70, -40, -50)
        #expect(move.lines(contacts) == ["G90", "G53 G0 X-70 Y-70", "G91"])
    }

    // MARK: Cylinder

    @Test func cylinderLongSidesAreTouchedAtHalfItsHeight() throws {
        let all = steps(cylinder)   // 200 long, Ø20: top view is 200 × 20
        // Ends: the normal 3 mm below the top.
        #expect(try step("Move outside the left side and lower", in: all).lines(ProbeContacts()).last
                == "G38.3 Z-13 F100")
        // Long sides: at the widest point, 10 mm (half the diameter) below the top.
        #expect(try step("Move outside the bottom side and lower", in: all).lines(ProbeContacts()).last
                == "G38.3 Z-20 F100")
    }

    // MARK: Circle: boss

    @Test func bossIsTouchedFromOutsideAtItsRadius() throws {
        var settings = ProbeSettings()
        settings.refinesCircle = false
        let all = steps(solidDisk, settings: settings)   // Ø50, center is the default kind

        #expect(try step("Move outside the left side of the stock and lower", in: all)
            .lines(ProbeContacts()).first == "G0 X-30")                       // −(25 + 5)
        #expect(try step("Back above the stock", in: all).lines(ProbeContacts()).last == "G0 X26")  // 25 + r
        #expect(all.filter { $0.title.hasPrefix("Touch the") && $0.title != "Touch the top" }.count == 4)
    }

    // MARK: Circle: hole

    @Test func holeTouchesTheTopOnTheRingThenGoesBack() throws {
        let all = steps(disk) { $0.circleSide = .inside }
        let titles = all.map(\.title)
        let ring = try #require(titles.firstIndex(of: "Move over the ring around the hole"))
        let touch = try #require(titles.firstIndex(of: "Touch the top"))
        let back = try #require(titles.firstIndex(of: "Back over the hole"))
        #expect(ring < touch && touch < back)

        #expect(all[ring].lines(ProbeContacts()) == ["G0 X16.25"])   // (50 + 15) / 4
        #expect(all[back].lines(ProbeContacts()) == ["G0 X-16.25"])
    }

    @Test func holeIsTouchedFromInsideAndReturnsToTheMiddle() throws {
        var settings = ProbeSettings()
        settings.refinesCircle = false
        let all = steps(disk, configure: { $0.circleSide = .inside }, settings: settings)

        #expect(try step("Touch the left wall", in: all).lines(ProbeContacts()).first == "G38.2 X20 F100")
        // Back from the wall by the hole's radius minus the ball's: 7.5 − 1.
        #expect(all.filter { $0.title == "Back to the middle of the hole" }
            .first?.lines(ProbeContacts()) == ["G0 X-6.5"])
        #expect(all.filter { $0.title == "Lower into the hole" }.count == 1)
    }

    @Test func circleIsTouchedTwiceByDefault() {
        let all = steps(disk) { $0.circleSide = .inside }
        #expect(all.filter { $0.title == "Lower into the hole" }.count == 2)
        #expect(all.contains { $0.measure == ProbeKey.side(.x, 1, pass: 1) })
        #expect(all.contains { $0.title == "Move to the center found so far" })
    }

    @Test func circleCenterMoveUsesTheLatestPass() throws {
        let all = steps(solidDisk)
        let last = try #require(all.last { $0.title == "Move to the center" })

        var contacts = ProbeContacts()
        // Pass 0 (rough) and pass 1 (the one that should be used).
        for (index, offset) in [0.0, 2.0].enumerated() {
            contacts[ProbeKey.side(.x, 1, pass: index)] = SIMD3(-100 + offset, 0, 0)
            contacts[ProbeKey.side(.x, -1, pass: index)] = SIMD3(-50 + offset, 0, 0)
            contacts[ProbeKey.side(.y, 1, pass: index)] = SIMD3(0, -90 + offset, 0)
            contacts[ProbeKey.side(.y, -1, pass: index)] = SIMD3(0, -40 + offset, 0)
        }
        #expect(last.lines(contacts) == ["G90", "G53 G0 X-73 Y-63", "G91"])
    }

    // MARK: Problems

    @Test func aHoleSmallerThanTheBallIsAProblem() {
        let tiny = StockGeometry.disk(outerDiameter: 10, innerDiameter: 2, depth: 8)
        var flow = ProbeFlow(geometry: tiny)
        flow.circleSide = .inside
        #expect(!ProbeCycleBuilder.problems(flow: flow, settings: ProbeSettings()).isEmpty)
    }

    @Test func tooThinStockIsAProblemForSidesButNotForZ() {
        let thin = StockGeometry.rectangular(width: 50, height: 50, depth: 1.5)
        var flow = ProbeFlow(geometry: thin)
        #expect(!ProbeCycleBuilder.problems(flow: flow, settings: ProbeSettings()).isEmpty)
        flow.kind = .zSurface
        #expect(ProbeCycleBuilder.problems(flow: flow, settings: ProbeSettings()).isEmpty)
    }

    @Test func settingsProblemsAreIncluded() {
        var settings = ProbeSettings()
        settings.ballDiameter = 0
        let flow = ProbeFlow(geometry: rectangle)
        #expect(!ProbeCycleBuilder.problems(flow: flow, settings: settings).isEmpty)
    }
}
