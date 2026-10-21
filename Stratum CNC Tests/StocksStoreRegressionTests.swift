import Foundation
import Testing
@testable import Stratum_CNC

struct StocksStoreRegressionTests {
    @Test @MainActor func preservesSavedLibraryAcrossLoads() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("materials.json")
        let stock = StockMaterial(name: "Custom stock", quantity: 7, material: .aluminum,
                                  geometry: .rectangular(width: 12, height: 34, depth: 5))
        let data = try JSONEncoder().encode(StockLibrary(stocks: [stock]))
        try data.write(to: url)

        let store = StocksStore(stocksFileURL: url)
        #expect(store.stocks == [stock])
        try store.load()
        #expect(store.stocks == [stock])
        #expect(try Data(contentsOf: url) == data)
    }
}
