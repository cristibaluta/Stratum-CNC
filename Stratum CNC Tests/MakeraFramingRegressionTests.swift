import Foundation
import Testing
@testable import Stratum_CNC

struct MakeraFramingRegressionTests {
    @Test(arguments: [0, 1, 2])
    func rejectsLengthsWithoutTypeAndCRC(length: UInt8) {
        let parser = MakeraFrameParser()
        let valid = MakeraFraming.buildFrame(ptype: MakeraFraming.ptypeNormalInfo,
                                            payload: Data("ok".utf8))
        let frames = parser.feed(Data([0x86, 0x68, 0x00, length]) + valid)
        #expect(frames.count == 1)
        #expect(frames.first?.payload == Data("ok".utf8))
    }

    @Test func acceptsFragmentedFrames() {
        let parser = MakeraFrameParser()
        let frame = MakeraFraming.buildFrame(ptype: MakeraFraming.ptypeNormalInfo,
                                            payload: Data("ok".utf8))
        let frames = frame.flatMap { parser.feed(Data([$0])) }
        #expect(frames.count == 1)
        #expect(frames.first?.payload == Data("ok".utf8))
    }
}
