import Testing
@testable import Stratum_CNC

struct HeaderToolKindRegressionTests {
    @Test func ballEndMillsUseRoundToolGeometry() throws {
        let tagged = MakeraHeaderParser().parse(headerLines: [
            ";@MKR|BEGIN", ";@MKR|TOOL|number=1|type=Ball End Mill|diameter=3", ";@MKR|END"
        ])
        let plain = MakeraCAMHeaderParser().parse(headerLines: ["; T1-3*10mm Ball End Mill"])
        #expect(try #require(tagged?.tools[1]).kind == .ballNose)
        #expect(try #require(plain?.tools[1]).kind == .ballNose)
    }
}
