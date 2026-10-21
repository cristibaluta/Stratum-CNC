import Foundation
import Testing
@testable import Stratum_CNC

struct MachineConnectionTests {
    @Test @MainActor func stoppedRunCannotStartAReplacementWithTheSameFilename() async throws {
        let keys = ["autoZBeforeRun", "lastUploadedRemotePath"]
        let oldValues = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, oldValues) { UserDefaults.standard.set(value, forKey: key) }
        }
        let model = ControllerModel()
        model.autoZBeforeRun = true
        model.connection.connect(to: .mock)
        defer { model.connection.disconnect() }
        // Acknowledge the first pre-run macro without a hardware connection.
        model.jobRunner.configure { _ in }
        model.uploader.onCompleted?("/sd/gcodes/same.nc")
        for _ in 0..<model.jobRunner.totalLines { model.jobRunner.handleMachineLine("ok") }
        try await Task.sleep(for: .milliseconds(20))
        model.stopJob()
        model.uploader.onCompleted?("/sd/gcodes/same.nc")
        model.connection.clearLogs()
        // The replacement macro is deliberately still waiting for its first acknowledgement.
        try await Task.sleep(for: .milliseconds(1100))
        #expect(model.jobRunner.isActive)
        #expect(!model.connection.rawLog.contains(where: { $0.hasPrefix("> play ") }))
    }

    @Test @MainActor func zeroingMockWorkCoordinatesDoesNotMoveTheMachine() throws {
        let simulator = MockMachineSimulator()
        simulator.handle(command: "G1 X10 Y20 Z30", reply: { _ in })
        simulator.handle(command: "G10L20P0X0Y0Z0", reply: { _ in })
        let raw = try #require(simulator.handleRealtime(.statusQuery))
        let status = try #require(MakeraMachineStatus.parse(raw))
        #expect(status.machinePosition.x == 10)
        #expect(status.machinePosition.y == 20)
        #expect(status.machinePosition.z == 30)
        #expect(status.workPosition.x == 0)
        #expect(status.workPosition.y == 0)
        #expect(status.workPosition.z == 0)
    }

    @Test @MainActor func disconnectStopsPendingControllerWork() async throws {
        let model = ControllerModel()
        model.connection.connect(to: .mock)
        model.startJob(lines: ["G1 X10", "G1 X20"])
        model.uploader.upload(fileName: "job.nc", contents: Data("G1 X1".utf8))
        model.connection.disconnect()
        #expect(!model.jobRunner.isActive)
        #expect(model.uploader.state == .failed("Connection closed"))
        model.connection.connect(to: .mock)
        defer { model.connection.disconnect() }
        model.connection.clearLogs()
        try await Task.sleep(for: .milliseconds(300))
        #expect(!model.connection.rawLog.contains(where: { $0.contains("G1 X20") || $0.hasPrefix("> play ") }))
    }

    @Test @MainActor func ignoresRepliesFromPreviousMockSession() async throws {
        let connection = MachineConnection()
        connection.connect(to: .mock)
        var replies: [String] = []
        connection.onLine = { replies.append($0) }
        connection.send("G1 X10")
        connection.connect(to: .mock)
        defer { connection.disconnect() }
        try await Task.sleep(for: .milliseconds(300))
        #expect(replies.isEmpty)
        #expect(connection.isConnected)
        #expect(connection.wireProtocol == .makera)
    }

    @Test @MainActor func cancelledSocketCannotDisconnectReplacementSession() async throws {
        let connection = MachineConnection()
        connection.connect(to: MakeraMachine(name: "Local test", ip: "127.0.0.1", port: 9, busy: false))
        connection.connect(to: .mock)
        defer { connection.disconnect() }
        try await Task.sleep(for: .milliseconds(300))
        #expect(connection.isConnected)
        #expect(connection.wireProtocol == .makera)
        #expect(connection.lastError == nil)
    }
}
