import Foundation
import Testing
@testable import Stratum_CNC

struct NCFileDocumentRegressionTests {
    @Test @MainActor func inMemoryLoadSupersedesPendingFileLoad() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".nc")
        defer { try? FileManager.default.removeItem(at: url) }
        try "G1 X1".write(to: url, atomically: true, encoding: .utf8)
        let document = NCFileDocument()
        document.load(from: url)
        document.load(from: "G1 X2")
        #expect(!document.isLoading)
        try await Task.sleep(for: .milliseconds(200))
        #expect(document.lines.map(\.text) == ["G1 X2"])
        #expect(document.fileURL == nil)
        #expect(document.fileName == "From CAM")
    }
}
