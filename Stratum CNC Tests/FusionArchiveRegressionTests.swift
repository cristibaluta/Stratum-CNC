import Foundation
import Testing
@testable import Stratum_CNC

struct FusionArchiveRegressionTests {
    @Test func truncatedCentralDirectoryThrowsInsteadOfIndexingPastEnd() throws {
        var bytes = [UInt8](repeating: 0, count: 68)
        bytes.replaceSubrange(0..<4, with: [0x50, 0x4B, 0x01, 0x02])
        bytes[28] = 255
        bytes[29] = 255
        bytes.replaceSubrange(46..<50, with: [0x50, 0x4B, 0x05, 0x06])
        bytes[56] = 1
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tools")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(bytes).write(to: url)
        #expect(throws: FusionImportError.self) {
            try FusionToolsImporter.importTools(from: url)
        }
    }
}
