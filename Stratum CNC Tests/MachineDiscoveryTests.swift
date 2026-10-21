import Foundation
import Network
import Testing
@testable import Stratum_CNC

struct MachineDiscoveryTests {
    @Test @MainActor func restartingDiscoveryIgnoresOldListenerEvents() async throws {
        let discovery = MachineDiscovery(port: .any)
        defer { discovery.stopScanning() }
        for _ in 0..<3 {
            discovery.startScanning()
            for _ in 0..<100 {
                if discovery.isScanning || discovery.lastError != nil { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(discovery.lastError == nil)
            #expect(discovery.isScanning)
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(discovery.isScanning)
        discovery.stopScanning()
        try await Task.sleep(for: .milliseconds(100))
        #expect(!discovery.isScanning)
        #expect(discovery.machines == [.mock])
    }
}
