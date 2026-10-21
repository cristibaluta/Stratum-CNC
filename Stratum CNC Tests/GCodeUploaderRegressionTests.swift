import Foundation
import Testing
@testable import Stratum_CNC

struct GCodeUploaderRegressionTests {
    @Test(arguments: [MakeraWireProtocol.makera, .smoothie])
    @MainActor func finalAcknowledgementCanArriveBeforeSendCompletion(wire: MakeraWireProtocol) {
        let uploader = GCodeUploader()
        var completedPaths: [String] = []
        uploader.onCompleted = { completedPaths.append($0) }
        uploader.configure(sendLine: { _ in }, sendRawBytes: { bytes, completion in
            if bytes == Data([0x04]) { uploader.handleMachineLine("Done saving file.") }
            completion(nil)
        }, sendFrame: { type, _, completion in
            if type == MakeraFraming.ptypeFileEnd { uploader.handleMachineLine("ok") }
            completion(nil)
        }, wireProtocol: { wire })
        uploader.upload(fileName: "job.nc", contents: Data("G1 X1".utf8))
        uploader.handleMachineLine("ready")
        #expect(uploader.state == .completed(remotePath: "/sd/gcodes/job.nc"))
        #expect(completedPaths == ["/sd/gcodes/job.nc"])
    }

    @Test(arguments: [false, true])
    @MainActor func transferErrorsNeverCompleteTheUpload(finishSending: Bool) {
        let uploader = GCodeUploader()
        var completed = false
        uploader.onCompleted = { _ in completed = true }
        uploader.configure(sendLine: { _ in },
                           sendRawBytes: { _, completion in if finishSending { completion(nil) } },
                           sendFrame: { _, _, completion in if finishSending { completion(nil) } },
                           wireProtocol: { .makera })
        uploader.upload(fileName: "job.nc", contents: Data("G1 X1".utf8))
        uploader.handleMachineLine("ready")
        uploader.handleMachineLine("error: file not saved")
        #expect(uploader.state == .failed("error: file not saved"))
        #expect(!completed)
    }

    @Test(arguments: [MakeraWireProtocol.makera, .smoothie])
    @MainActor func cancelledTransferCannotResumeFromLateCallback(wire: MakeraWireProtocol) throws {
        let uploader = GCodeUploader()
        var completions: [(Error?) -> Void] = []
        uploader.configure(sendLine: { _ in },
                           sendRawBytes: { _, completion in completions.append(completion) },
                           sendFrame: { _, _, completion in completions.append(completion) },
                           wireProtocol: { wire })
        uploader.upload(fileName: "old.nc", contents: Data("G1 X1".utf8))
        uploader.handleMachineLine("ready")
        let oldCompletion = try #require(completions.first)
        uploader.cancel()
        oldCompletion(nil)
        #expect(uploader.state == .cancelled)

        uploader.upload(fileName: "new.nc", contents: Data("G1 X2".utf8))
        uploader.handleMachineLine("ready")
        let sends = completions.count
        oldCompletion(nil)
        #expect(completions.count == sends)
        #expect(uploader.state == .transferring(bytesSent: 0, totalBytes: 5))
        uploader.cancel()
    }
}
