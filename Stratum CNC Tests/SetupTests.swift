import Testing
import Foundation
import CoreGraphics
import simd
@testable import Stratum_CNC

// A 40 (Y, front to back) x 10 (Z) block, front edge at Y = 0, top at Z = 0: the frame the
// stock is assumed to sit in (see `StockMaterial.setupExtents`).

private func frame(_ face: SetupFace, width: Double = 40, height: Double = 10) -> SetupFrame {
    let turns = face.rawValue / 90
    let up = turns % 2 == 0 ? height : width
    return face == .top
        ? .identity
        : SetupFrame(angle: face.angle, axisY: width / 2, axisZ: -height / 2, surfaceDistance: up / 2)
}

private func corners(width: Double = 40, height: Double = 10) -> [SIMD3<Double>] {
    [0, width].flatMap { y in [-height, 0].map { z in SIMD3<Double>(3, y, z) } }
}

@Suite struct SetupFrameTests {

    @Test func topIsTheIdentity() {
        let point = SIMD3<Double>(1, 2, -3)
        #expect(frame(.top).map(point) == point)
        #expect(frame(.top).isIdentity)
    }

    @Test func theFaceOfTheSetupEndsUpAtZ0() {
        // The front face is Y = 0, the back one Y = 40, the bottom one Z = -10
        #expect(frame(.front).map(SIMD3(5, 0, -4)).z == 0)
        #expect(frame(.back).map(SIMD3(5, 40, -4)).z == 0)
        #expect(frame(.bottom).map(SIMD3(5, 12, -10)).z == 0)
    }

    @Test func theStockAlwaysLiesBelowZ0() {
        for face in SetupFace.allCases {
            let zs = corners().map { frame(face).map($0).z }
            #expect(zs.max()! <= 1e-12, "\(face.title)")
            #expect(zs.min()! < -1e-9, "\(face.title)")
        }
    }

    @Test func bottomMirrorsYAboutTheCentreAndKeepsX() {
        let mapped = frame(.bottom).map(SIMD3(7, 10, 0))
        #expect(mapped.x == 7)
        #expect(mapped.y == 30)
        // The top of the part is now the deepest point: the whole thickness below z0
        #expect(mapped.z == -10)
    }

    @Test func frontAndBackStandTheStockOnItsEdge() {
        // 10 wide in Y, 40 deep in Z, centred on the axis
        for face in [SetupFace.front, .back] {
            let mapped = corners().map { frame(face).map($0) }
            #expect(mapped.map(\.y).min()! == 15)
            #expect(mapped.map(\.y).max()! == 25)
            #expect(mapped.map(\.z).min()! == -40)
        }
    }

    @Test func frontAndBackAreOppositeSides() {
        // A feature near the front edge is cut from Front, one near the back edge from Back
        let nearFront = SIMD3<Double>(0, 2, -5)
        #expect(frame(.front).map(nearFront).z > frame(.back).map(nearFront).z)
    }

    @Test func turningFourQuartersComesBackToTheStart() {
        // Mapping by 90 four times about the same axis (no surface drop) is the identity
        let c = SIMD3<Double>(0, 20, -5)
        var point = SIMD3<Double>(1, 33, -2)
        let start = point
        let quarter = SetupFrame(angle: 90, axisY: c.y, axisZ: c.z, surfaceDistance: 0)
        for _ in 0..<4 { point = quarter.map(point) }
        #expect(abs(point.y - start.y) < 1e-12 && abs(point.z - start.z) < 1e-12)
    }

    @Test func previewOfTheBottomIsMirroredBack() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 10))
        path.addLine(to: CGPoint(x: 5, y: 10))
        let back = frame(.bottom).previewInPartFrame(path)
        #expect(back?.boundingBox.minY == 30)
        #expect(frame(.front).previewInPartFrame(path) == nil)
        #expect(frame(.top).previewInPartFrame(path) === path)
    }
}

@Suite struct SetupModelTests {

    @Test func anglesAreKeptInZeroTo360() {
        #expect(Setup(name: "x", angle: -90).angle == 270)
        #expect(Setup(name: "x", angle: 450).angle == 90)
    }

    @Test func facesFollowTheAngle() {
        #expect(Setup(face: .front).face == .front)
        #expect(Setup(name: "x", angle: 45).face == nil)
        #expect(Setup(name: "x", angle: 45).orientationTitle == "45°")
    }

    @Test func namesAreUnique() {
        #expect(Setup.uniqueName(for: .front, among: []) == "Front")
        #expect(Setup.uniqueName(for: .front, among: ["Front"]) == "Front 2")
        #expect(Setup.uniqueName(for: .front, among: ["Front", "Front 2"]) == "Front 3")
    }

    @Test func toolpathDataWithoutASetupStillDecodes() throws {
        var toolpath = ToolpathDataFixture.make()
        toolpath.setupID = nil
        let data = try JSONEncoder().encode(toolpath)
        let decoded = try JSONDecoder().decode(ToolpathData.self, from: data)
        #expect(decoded.setupID == nil)

        toolpath.setupID = UUID()
        let again = try JSONDecoder().decode(ToolpathData.self, from: JSONEncoder().encode(toolpath))
        #expect(again.setupID == toolpath.setupID)
    }
}

/// The smallest toolpath the memberwise initializer accepts (the values don't matter here).
private enum ToolpathDataFixture {
    static func make() -> ToolpathData {
        ToolpathData(id: UUID(),
                     name: "Contour 1",
                     tool: Tool(id: UUID(), name: "3mm", shankDiameter: 3, toolDiameter: 3, cuttingHeight: 12,
                                type: .endMill, group: nil, tipAngle: nil, presets: []),
                     startZ: 0, endZ: -1, contour: .onContour,
                     ramping: RampingSettings(enabled: true, type: .linear, angle: 2, length: 10),
                     feedRate: 800, plungeRate: 400, spindleRPM: 12000,
                     stepDown: 0.1, stepOverPercent: 40, safeZ: 3)
    }
}
