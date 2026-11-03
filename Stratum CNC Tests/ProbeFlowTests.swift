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

    @Test func circleOffersOnlyZAndCenter() {
        var flow = ProbeFlow(geometry: rectangle)
        flow.setShape(.circle)
        #expect(flow.availableKinds == [.zSurface, .center])
    }

    @Test func switchingToCircleFallsBackToCenter() {
        var flow = ProbeFlow(geometry: rectangle)
        flow.kind = .corner
        flow.setShape(.circle)
        #expect(flow.kind == .center)
    }

    @Test func switchingToCircleKeepsZSurface() {
        var flow = ProbeFlow(geometry: rectangle)
        flow.kind = .zSurface
        flow.setShape(.circle)
        #expect(flow.kind == .zSurface)
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
