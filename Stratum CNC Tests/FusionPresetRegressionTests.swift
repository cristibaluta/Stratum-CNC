import Foundation
import Testing
@testable import Stratum_CNC

struct FusionPresetRegressionTests {
    @Test func oversizedSpindleSpeedsDoNotCrashImport() throws {
        let json = #"{"data":[{"guid":"test","type":"flat end mill","geometry":{"DC":3},"start-values":{"presets":[{"name":"Test","n":1e100,"n_ramp":12000.4}]}}]}"#
        let result = try FusionToolsImporter.convert(json: Data(json.utf8))
        let preset = try #require(result.tools.first?.presets.first)
        #expect(preset.spindleRPM == nil)
        #expect(preset.rampSpindleRPM == 12000)
    }
}
