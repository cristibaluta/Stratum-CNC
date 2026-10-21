import Foundation
import Testing
@testable import Stratum_CNC

struct ArchiveEntryPathRegressionTests {
    @Test(arguments: ["../outside.gbr", "nested/../../outside.gbr", ".", ".."])
    func rejectsEntriesOutsideExtractionRoot(entry: String) {
        let root = URL(fileURLWithPath: "/tmp/gerber-import")
        #expect(ArchiveEntryPath.destination(for: entry, in: root) == nil)
    }

    @Test func acceptsNestedGerberFiles() {
        let root = URL(fileURLWithPath: "/tmp/gerber-import")
        #expect(ArchiveEntryPath.destination(for: "board/top.gtl", in: root)?.path == "/tmp/gerber-import/board/top.gtl")
    }
}
