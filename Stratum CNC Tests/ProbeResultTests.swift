import Testing
import Foundation
@testable import Stratum_CNC

struct ProbeResultTests {

    // Ball Ø2, so r = 1.
    private let rectangle = StockGeometry.rectangular(width: 100, height: 60, depth: 10)
    private let disk = StockGeometry.disk(outerDiameter: 50, innerDiameter: 15, depth: 13)
    private let solidDisk = StockGeometry.disk(outerDiameter: 50, innerDiameter: 0, depth: 13)

    private func result(_ geometry: StockGeometry,
                        configure: (inout ProbeFlow) -> Void = { _ in },
                        contacts: ProbeContacts,
                        bedMin: SIMD2<Double>? = nil,
                        bedMax: SIMD2<Double>? = nil) -> ProbeResult {
        var flow = ProbeFlow(geometry: geometry)
        configure(&flow)
        return ProbeResult(flow: flow, settings: ProbeSettings(), contacts: contacts,
                           bedMin: bedMin, bedMax: bedMax)
    }

    private func contacts(_ values: [String: (Double, Double)]) -> ProbeContacts {
        var result = ProbeContacts()
        for (key, point) in values {
            result[key] = SIMD3(point.0, point.1, -50)
        }
        return result
    }

    // MARK: Edges

    @Test func theSurfaceIsTheContactPlusDirectionTimesRadius() {
        var contacts = ProbeContacts()
        contacts[ProbeKey.side(.x, 1)] = SIMD3(-180, 0, 0)    // moving +X: ball center is 1 short of the left side
        contacts[ProbeKey.side(.x, -1)] = SIMD3(-80, 0, 0)    // moving −X: 1 short of the right side
        #expect(ProbeResult.edge(contacts, .x, 1, pass: 0, radius: 1) == -179)
        #expect(ProbeResult.edge(contacts, .x, -1, pass: 0, radius: 1) == -81)
    }

    @Test func missingContactGivesNoEdge() {
        #expect(ProbeResult.edge(ProbeContacts(), .x, 1, pass: 0, radius: 1) == nil)
    }

    // MARK: Z

    @Test func zOnlyHasASurfaceAndNoOrigin() {
        var contacts = ProbeContacts()
        contacts[ProbeKey.zTop] = SIMD3(-100, -100, -42.5)
        let probed = result(rectangle, configure: { $0.kind = .zSurface }, contacts: contacts)
        #expect(probed.surfaceZ == -42.5)
        #expect(!probed.hasOrigin)
        #expect(probed.originCommand(workCoordinateSystem: 1) == nil)
    }

    // MARK: Corner

    @Test func bottomLeftCornerSetsTheOriginAtTheLeftAndBottomSides() {
        let probed = result(rectangle, configure: { $0.corner = .bottomLeft },
                            contacts: contacts([ProbeKey.side(.x, 1): (-180, -150),
                                                ProbeKey.side(.y, 1): (-170, -170)]))
        #expect(probed.originX == -179)
        #expect(probed.originY == -169)
        #expect(probed.originCommand(workCoordinateSystem: 1) == "G10 L2 P1 X-179 Y-169")
    }

    @Test func topRightCornerSetsTheOriginAtTheRightAndTopSides() {
        let probed = result(rectangle, configure: { $0.corner = .topRight },
                            contacts: contacts([ProbeKey.side(.x, -1): (-80, -150),
                                                ProbeKey.side(.y, -1): (-120, -100)]))
        #expect(probed.originX == -81)
        #expect(probed.originY == -101)
    }

    @Test func aMissingSideLeavesThatAxisUnset() {
        let probed = result(rectangle, configure: { $0.corner = .bottomLeft },
                            contacts: contacts([ProbeKey.side(.x, 1): (-180, 0)]))
        #expect(probed.originX == -179)
        #expect(probed.originY == nil)
        #expect(probed.originCommand(workCoordinateSystem: 2) == "G10 L2 P2 X-179")
    }

    // MARK: Edge

    @Test func rightEdgeSetsOnlyX() {
        let probed = result(rectangle, configure: {
            $0.kind = .edge
            $0.edge = .right
        }, contacts: contacts([ProbeKey.side(.x, -1): (-80, 0)]))
        #expect(probed.originX == -81)
        #expect(probed.originY == nil)
        #expect(probed.originCommand(workCoordinateSystem: 1) == "G10 L2 P1 X-81")
    }

    // MARK: Rectangle center

    private var centeredRectangle: ProbeContacts {
        // Left side at X −120, right side at −20; bottom at Y −100, top at −40.
        // The ball center stops 1 mm short of each: −121, −19, −101, −39.
        contacts([ProbeKey.side(.x, 1): (-121, -70),
                  ProbeKey.side(.x, -1): (-19, -70),
                  ProbeKey.side(.y, 1): (-70, -101),
                  ProbeKey.side(.y, -1): (-70, -39)])
    }

    @Test func rectangleCenterIsTheMiddleAndTheSizeIsMeasured() {
        let probed = result(rectangle, configure: { $0.kind = .center }, contacts: centeredRectangle)
        #expect(probed.originX == -70)
        #expect(probed.originY == -70)
        #expect(probed.rows.contains { $0.label == "Width" && $0.value == "100.000 mm" })
        #expect(probed.rows.contains { $0.label == "Height" && $0.value == "60.000 mm" })
        #expect(probed.warnings.isEmpty)
    }

    @Test func aWrongSizedStockIsReported() {
        let wrong = StockGeometry.rectangular(width: 120, height: 60, depth: 10)
        let probed = result(wrong, configure: { $0.kind = .center }, contacts: centeredRectangle)
        #expect(probed.warnings.count == 1)
        #expect(probed.warnings.first?.contains("width") == true)
    }

    @Test func smallSizeDifferencesAreNotReported() {
        let close = StockGeometry.rectangular(width: 100.6, height: 59.5, depth: 10)
        let probed = result(close, configure: { $0.kind = .center }, contacts: centeredRectangle)
        #expect(probed.warnings.isEmpty)
    }

    // MARK: Circle

    @Test func bossCenterAndDiameter() {
        // Ø50 boss centered at X −50, Y −60. Touched from outside: the ball
        // center stops 1 mm short of the surface, on the outside.
        let probed = result(solidDisk, contacts: contacts([
            ProbeKey.side(.x, 1, pass: 0): (-76, -60),    // left surface −75
            ProbeKey.side(.x, -1, pass: 0): (-24, -60),   // right surface −25
            ProbeKey.side(.y, 1, pass: 0): (-50, -86),    // bottom surface −85
            ProbeKey.side(.y, -1, pass: 0): (-50, -34),   // top surface −35
        ]))
        #expect(probed.originX == -50)
        #expect(probed.originY == -60)
        #expect(probed.rows.contains { $0.label == "Diameter (X)" && $0.value == "50.000 mm" })
        #expect(probed.warnings.isEmpty)
    }

    @Test func holeCenterAndDiameter() {
        // Ø15 hole centered at X −50, Y −60. Touched from inside: the ball
        // center stops 1 mm short of the wall, toward the middle.
        let probed = result(disk, configure: { $0.circleSide = .inside }, contacts: contacts([
            ProbeKey.side(.x, 1, pass: 0): (-43.5, -60),   // right wall −42.5
            ProbeKey.side(.x, -1, pass: 0): (-56.5, -60),  // left wall −57.5
            ProbeKey.side(.y, 1, pass: 0): (-50, -53.5),   // top wall −52.5
            ProbeKey.side(.y, -1, pass: 0): (-50, -66.5),  // bottom wall −67.5
        ]))
        #expect(probed.originX == -50)
        #expect(probed.originY == -60)
        #expect(probed.rows.contains { $0.label == "Diameter (X)" && $0.value == "15.000 mm" })
        #expect(probed.warnings.isEmpty)
    }

    @Test func theRefinedPassIsUsedWhenItExists() {
        let probed = result(solidDisk, contacts: contacts([
            ProbeKey.side(.x, 1, pass: 0): (-90, 0), ProbeKey.side(.x, -1, pass: 0): (-30, 0),
            ProbeKey.side(.y, 1, pass: 0): (0, -90), ProbeKey.side(.y, -1, pass: 0): (0, -30),
            ProbeKey.side(.x, 1, pass: 1): (-76, 0), ProbeKey.side(.x, -1, pass: 1): (-24, 0),
            ProbeKey.side(.y, 1, pass: 1): (0, -86), ProbeKey.side(.y, -1, pass: 1): (0, -34),
        ]))
        #expect(probed.originX == -50)
        #expect(probed.originY == -60)
    }

    @Test func aWrongDiameterIsReported() {
        let probed = result(solidDisk, contacts: contacts([
            ProbeKey.side(.x, 1, pass: 0): (-71, 0), ProbeKey.side(.x, -1, pass: 0): (-29, 0),
            ProbeKey.side(.y, 1, pass: 0): (0, -81), ProbeKey.side(.y, -1, pass: 0): (0, -39),
        ]))
        #expect(!probed.warnings.isEmpty)
    }

    // MARK: Bed

    @Test func anOriginOffTheBedIsReported() {
        let probed = result(rectangle, configure: { $0.corner = .bottomLeft },
                            contacts: contacts([ProbeKey.side(.x, 1): (20, 0), ProbeKey.side(.y, 1): (0, -170)]),
                            bedMin: SIMD2(-200, -200), bedMax: SIMD2(0, 0))
        #expect(probed.warnings.count == 1)   // X 21 is past the home side; Y is fine
    }

    // MARK: Canvas offset

    @Test func canvasOffsetIsTheOriginMinusTheAnchor() {
        let probed = result(rectangle, configure: { $0.corner = .bottomLeft },
                            contacts: contacts([ProbeKey.side(.x, 1): (-180, 0), ProbeKey.side(.y, 1): (0, -170)]))
        let offset = probed.xyOffset(anchor: SIMD2(-185, -185), current: SIMD2(0, 0))
        #expect(offset == SIMD2(6, 16))   // origin (−179, −169) − anchor (−185, −185)
    }

    @Test func anUnmeasuredAxisKeepsTheCurrentCanvasOffset() {
        let probed = result(rectangle, configure: {
            $0.kind = .edge
            $0.edge = .left
        }, contacts: contacts([ProbeKey.side(.x, 1): (-180, 0)]))
        let offset = probed.xyOffset(anchor: SIMD2(-185, -185), current: SIMD2(3, 9))
        #expect(offset == SIMD2(6, 9))
    }

    // MARK: Run-start lines

    @Test func runStartLinesThatCarryTheOriginAreRecognised() {
        let probed = result(rectangle, configure: { $0.corner = .bottomLeft },
                            contacts: contacts([ProbeKey.side(.x, 1): (-180, 0), ProbeKey.side(.y, 1): (0, -170)]))
        #expect(probed.isCarried(by: ["G92.1", "G54", "G10 L2 P1 X-179 Y-169"]))
        #expect(probed.isCarried(by: ["G10 L2 P1 X-179.0004 Y-168.9996"]))
    }

    @Test func runStartLinesThatDifferAreFlagged() {
        let probed = result(rectangle, configure: { $0.corner = .bottomLeft },
                            contacts: contacts([ProbeKey.side(.x, 1): (-180, 0), ProbeKey.side(.y, 1): (0, -170)]))
        #expect(!probed.isCarried(by: ["G10 L2 P1 X6 Y16"]))
        #expect(!probed.isCarried(by: []))
    }

    // MARK: Undo

    @Test func undoPutsBackOnlyTheAxesThatWereChanged() {
        let both = ProbeAppliedOrigin(workCoordinateSystem: 1, changedX: true, changedY: true,
                                      previousXYOffset: SIMD2(0, 0),
                                      previousMachineOrigin: SIMD2(-185.5, -184))
        #expect(both.revertCommand == "G10 L2 P1 X-185.5 Y-184")

        let onlyX = ProbeAppliedOrigin(workCoordinateSystem: 2, changedX: true, changedY: false,
                                       previousXYOffset: SIMD2(0, 0),
                                       previousMachineOrigin: SIMD2(-185.5, -184))
        #expect(onlyX.revertCommand == "G10 L2 P2 X-185.5")
    }

    @Test func undoNeedsToKnowTheOldOrigin() {
        let unknown = ProbeAppliedOrigin(workCoordinateSystem: 1, changedX: true, changedY: true,
                                         previousXYOffset: SIMD2(0, 0), previousMachineOrigin: nil)
        #expect(unknown.revertCommand == nil)
    }
}
