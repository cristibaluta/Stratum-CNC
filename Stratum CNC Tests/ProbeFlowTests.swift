import Testing
import Foundation
@testable import Stratum_CNC

struct ProbeFlowTests {

    private let rectangle = StockGeometry.rectangular(width: 100, height: 60, depth: 10)
    private let disk = StockGeometry.disk(outerDiameter: 50, innerDiameter: 15, depth: 13)
    private let cylinder = StockGeometry.cylindrical(diameter: 20, length: 200)

    // MARK: Defaults from the stock

    @Test func defaultsFollowTheStock() {
        #expect(ProbeFlow(geometry: rectangle).shape == .rectangle)
        #expect(ProbeFlow(geometry: cylinder).shape == .rectangle)
        #expect(ProbeFlow(geometry: disk).shape == .circle)
        #expect(ProbeFlow(geometry: disk).circleSide == .inside)
        #expect(ProbeFlow(geometry: disk).kind == .center)
        #expect(ProbeFlow(geometry: rectangle).kind == .corner)
    }

    @Test func cylinderFootprintIsLengthByDiameter() {
        let size = ProbeFlow.footprint(of: cylinder)
        #expect(size.width == 200)
        #expect(size.height == 20)
    }

    // MARK: Choosing

    @Test func rectangleOffersEveryKind() {
        #expect(ProbeFlow(geometry: rectangle).availableKinds == ProbeKind.allCases)
        #expect(ProbeFlow(geometry: cylinder).availableKinds == ProbeKind.allCases)
    }

    @Test func roundStockOffersOnlyZAndCenter() {
        #expect(ProbeFlow(geometry: disk).availableKinds == [.zSurface, .center])
    }

    @Test func onlyADiskWithAHoleAsksOutsideOrInside() {
        var flow = ProbeFlow(geometry: disk)
        #expect(flow.hasHole)
        #expect(flow.needsCircleSide)
        flow.kind = .zSurface
        #expect(!flow.needsCircleSide)

        let solid = ProbeFlow(geometry: .disk(outerDiameter: 40, innerDiameter: 0, depth: 8))
        #expect(!solid.hasHole)
        #expect(!solid.needsCircleSide)
        #expect(solid.circleSide == .outside)
    }

    @Test func zSurfaceIsTheOnlyKindThatSkipsZFirst() {
        var flow = ProbeFlow(geometry: rectangle)
        flow.kind = .zSurface
        #expect(!flow.probesZFirst)
        flow.kind = .edge
        #expect(flow.probesZFirst)
    }

    // MARK: Steps

    @Test func advancesAndGoesBack() {
        var flow = ProbeFlow(geometry: rectangle)
        flow.advance()
        #expect(flow.step == .position)
        flow.goBack()
        #expect(flow.step == .what)
        flow.goBack()
        #expect(flow.step == .what)
    }

    @Test func stopsAtTheLastStep() {
        var flow = ProbeFlow(geometry: rectangle)
        for _ in 0..<10 { flow.advance() }
        #expect(flow.step == .result)
        #expect(!flow.canAdvance)
    }

    // MARK: Where to jog

    @Test func cornerTargetsSitInsideTheStock() {
        var flow = ProbeFlow(geometry: rectangle)   // 100 × 60
        flow.kind = .corner

        flow.corner = .bottomLeft
        #expect(flow.targetPoint(inset: 10) == (10, 10))
        flow.corner = .bottomRight
        #expect(flow.targetPoint(inset: 10) == (90, 10))
        flow.corner = .topLeft
        #expect(flow.targetPoint(inset: 10) == (10, 50))
        flow.corner = .topRight
        #expect(flow.targetPoint(inset: 10) == (90, 50))
    }

    @Test func insetShrinksOnSmallStock() {
        let small = StockGeometry.rectangular(width: 20, height: 20, depth: 5)
        #expect(ProbeFlow.clampedInset(10, width: 20, height: 20) == 5)
        var flow = ProbeFlow(geometry: small)
        flow.corner = .topRight
        #expect(flow.targetPoint(inset: 10) == (15, 15))
    }

    @Test func centerTargetIsTheMiddle() {
        var flow = ProbeFlow(geometry: rectangle)
        flow.kind = .center
        #expect(flow.targetPoint(inset: 10) == (50, 30))
    }

    @Test func edgeTargetsAreOnTheMiddleOfTheSide() {
        var flow = ProbeFlow(geometry: rectangle)
        flow.kind = .edge
        flow.edge = .left
        #expect(flow.targetPoint(inset: 10) == (10, 30))
        flow.edge = .top
        #expect(flow.targetPoint(inset: 10) == (50, 50))
    }

    @Test func zOnADiskWithAHoleTouchesTheRing() {
        var flow = ProbeFlow(geometry: disk)   // Ø50 with a Ø15 hole
        flow.kind = .zSurface
        let target = flow.targetPoint(inset: 10)
        // Halfway between the hole's edge (7.5) and the outer edge (25) from the center.
        #expect(target.x == 25 + (50 + 15) / 4)
        #expect(target.y == 25)
    }

    // MARK: Touch points

    @Test func cornerTouchesOneSideInXAndOneInY() {
        var flow = ProbeFlow(geometry: rectangle)   // 100 × 60
        flow.corner = .topRight
        let points = flow.touchPoints(inset: 10)
        #expect(points.count == 2)
        #expect(points[0] == (100, 50))   // right side, at the dot's Y
        #expect(points[1] == (90, 60))    // top side, at the dot's X
    }

    @Test func edgeTouchesOnlyItsSide() {
        var flow = ProbeFlow(geometry: rectangle)
        flow.kind = .edge
        flow.edge = .bottom
        let points = flow.touchPoints(inset: 10)
        #expect(points.count == 1)
        #expect(points[0] == (50, 0))
    }

    @Test func zSurfaceTouchesNoSide() {
        var flow = ProbeFlow(geometry: rectangle)
        flow.kind = .zSurface
        #expect(flow.touchPoints(inset: 10).isEmpty)
    }

    @Test func rectangleCenterTouchesAllFourSides() {
        var flow = ProbeFlow(geometry: rectangle)
        flow.kind = .center
        let points = flow.touchPoints(inset: 10)
        #expect(points.count == 4)
        #expect(points[0] == (0, 30))
        #expect(points[1] == (100, 30))
        #expect(points[2] == (50, 0))
        #expect(points[3] == (50, 60))
    }

    @Test func holeCenterTouchesTheHoleWall() {
        var flow = ProbeFlow(geometry: disk)   // Ø50 with a Ø15 hole
        flow.circleSide = .inside
        let points = flow.touchPoints(inset: 10)
        #expect(points[0] == (25 - 7.5, 25))
        #expect(points[1] == (25 + 7.5, 25))
    }

    @Test func bossCenterTouchesTheOutside() {
        var flow = ProbeFlow(geometry: disk)
        flow.circleSide = .outside
        let points = flow.touchPoints(inset: 10)
        #expect(points[0] == (0, 25))
        #expect(points[1] == (50, 25))
    }

    // MARK: Instructions

    @Test func instructionsNameTheProbeTool() {
        var settings = ProbeSettings()
        settings.probeTool = 0
        let steps = ProbeFlow(geometry: rectangle).instructions(settings: settings)
        #expect(steps.first?.contains("T0") == true)
    }

    @Test func zOnlyHasNoSideDepthStep() {
        var flow = ProbeFlow(geometry: rectangle)
        flow.kind = .zSurface
        let steps = flow.instructions(settings: ProbeSettings())
        #expect(!steps.contains { $0.contains("below it") })
    }

    @Test func cornerInstructionsMentionTheSideDepth() {
        let steps = ProbeFlow(geometry: rectangle).instructions(settings: ProbeSettings())
        #expect(steps.contains { $0.contains("3 mm below it") })
    }

    @Test func holeInstructionsSayZIsTouchedOnTheRing() {
        var flow = ProbeFlow(geometry: disk)
        flow.circleSide = .inside
        #expect(flow.probesInsideHole)
        let steps = flow.instructions(settings: ProbeSettings())
        #expect(steps.contains { $0.contains("ring") })
    }

    // MARK: Settings

    @Test func edgeDepthNeverGoesUnderTheStock() {
        let settings = ProbeSettings()   // edgeDepth 3
        #expect(settings.edgeDepth(forStockThickness: 10) == 3)
        #expect(settings.edgeDepth(forStockThickness: 3) == 2)
        #expect(settings.edgeDepth(forStockThickness: 1) == 0.5)
    }

    @Test func workCoordinateSystemNames() {
        var settings = ProbeSettings()
        #expect(settings.workCoordinateSystemName == "G54")
        settings.workCoordinateSystem = 6
        #expect(settings.workCoordinateSystemName == "G59")
    }

    @Test func defaultSettingsAreValid() {
        #expect(ProbeSettings().problems.isEmpty)
    }

    @Test func badSettingsAreReported() {
        var settings = ProbeSettings()
        settings.ballDiameter = 0
        settings.measureFeed = 500
        #expect(settings.problems.count == 2)
    }

    @Test func settingsSurviveSaveAndLoad() throws {
        let suite = "ProbeSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var settings = ProbeSettings()
        settings.safeZ = 25
        settings.ballDiameter = 3
        settings.save(to: defaults)

        #expect(ProbeSettings.load(from: defaults) == settings)
    }

    @Test func missingSettingsLoadAsDefaults() throws {
        let suite = "ProbeSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(ProbeSettings.load(from: defaults) == ProbeSettings())
    }
}
