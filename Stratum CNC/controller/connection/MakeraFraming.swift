//
//  MakeraMachine.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.08.2026.
//

import Foundation

/// Makera's binary framed wire protocol.
///
/// Wire layout (big-endian): header(2) | length(2) | type(1) | payload(N) | crc(2) | footer(2)
/// Ported directly from Carvera_Controller/carveracontroller/protocols/framing.py + makera.py
enum MakeraFraming {
    static let frameHeader: UInt16 = 0x8668
    static let frameEnd: UInt16 = 0x55AA

    static let ptypeCtrlSingle: UInt8 = 0xA1   // realtime single-byte control (e.g. "?")
    static let ptypeCtrlMulti: UInt8 = 0xA2    // multi-byte command / gcode line
    static let ptypeFileStart: UInt8 = 0xB0
    static let ptypeFileMD5: UInt8 = 0xB1
    static let ptypeFileView: UInt8 = 0xB2
    static let ptypeFileData: UInt8 = 0xB3
    static let ptypeFileEnd: UInt8 = 0xB4
    static let ptypeFileCancel: UInt8 = 0xB5
    static let ptypeFileRetry: UInt8 = 0xB6
    static let ptypeStatusRes: UInt8 = 0x81
    static let ptypeDiagRes: UInt8 = 0x82
    static let ptypeLoadInfo: UInt8 = 0x83
    static let ptypeLoadFinish: UInt8 = 0x84
    static let ptypeLoadError: UInt8 = 0x85
    static let ptypeNormalInfo: UInt8 = 0x90

    static let maxFrameDataLength = 8200

    static let fileTransferTypes: Set<UInt8> = [
        ptypeFileStart, ptypeFileMD5, ptypeFileView,
        ptypeFileData, ptypeFileEnd, ptypeFileCancel, ptypeFileRetry,
    ]

    // MARK: - CRC-16/CCITT (poly 0x1021, init 0x0000)

    private static let crcTable: [UInt16] = {
        var table = [UInt16](repeating: 0, count: 256)
        for i in 0..<256 {
            var crc = UInt16(i) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
            table[i] = crc
        }
        return table
    }()

    static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0
        for byte in bytes {
            let index = Int(((crc >> 8) ^ UInt16(byte)) & 0xFF)
            crc = (crc << 8) ^ crcTable[index]
        }
        return crc
    }

    // MARK: - Building outbound frames

    static func buildFrame(ptype: UInt8, payload: Data) -> Data {
        let dataLength = UInt16(1 + payload.count + 2) // type + payload + crc
        var body = [UInt8]()
        body.append(UInt8(dataLength >> 8))
        body.append(UInt8(dataLength & 0xFF))
        body.append(ptype)
        body.append(contentsOf: payload)

        let crc = crc16(body)

        var frame = Data()
        frame.append(UInt8(frameHeader >> 8))
        frame.append(UInt8(frameHeader & 0xFF))
        frame.append(contentsOf: body)
        frame.append(UInt8(crc >> 8))
        frame.append(UInt8(crc & 0xFF))
        frame.append(UInt8(frameEnd >> 8))
        frame.append(UInt8(frameEnd & 0xFF))
        return frame
    }
}

struct MakeraParsedFrame {
    let ptype: UInt8
    let payload: Data
}

/// Streaming, stateful parser for inbound Makera-protocol frames.
/// Feed raw bytes as they arrive over the socket; it returns zero or more
/// complete, CRC-validated frames per call.
final class MakeraFrameParser {
    private enum State {
        case waitHeader
        case readLength
        case readData
        case checkFooter
    }

    private var state: State = .waitHeader
    private var headerBuf: [UInt8] = [0, 0]
    private var footerBuf: [UInt8] = [0, 0]
    private var packetData: [UInt8] = []
    private var bytesNeeded = 2
    private var expectedLength = 0

    func reset() {
        state = .waitHeader
        headerBuf = [0, 0]
        footerBuf = [0, 0]
        packetData.removeAll()
        bytesNeeded = 2
        expectedLength = 0
    }

    func feed(_ data: Data) -> [MakeraParsedFrame] {
        var frames: [MakeraParsedFrame] = []
        for byte in data {
            if let frame = feedByte(byte) {
                frames.append(frame)
            }
        }
        return frames
    }

    private func feedByte(_ byte: UInt8) -> MakeraParsedFrame? {
        switch state {
        case .waitHeader:
            headerBuf[0] = headerBuf[1]
            headerBuf[1] = byte
            let checksum = (UInt16(headerBuf[0]) << 8) | UInt16(headerBuf[1])
            if checksum == MakeraFraming.frameHeader {
                state = .readLength
                bytesNeeded = 2
                packetData.removeAll()
            }
            return nil

        case .readLength:
            packetData.append(byte)
            bytesNeeded -= 1
            if bytesNeeded == 0 {
                expectedLength = (Int(packetData[0]) << 8) | Int(packetData[1])
                if expectedLength >= 0 && expectedLength <= MakeraFraming.maxFrameDataLength {
                    state = .readData
                    bytesNeeded = expectedLength
                } else {
                    state = .waitHeader
                }
            }
            return nil

        case .readData:
            packetData.append(byte)
            bytesNeeded -= 1
            if bytesNeeded == 0 {
                state = .checkFooter
                bytesNeeded = 2
            }
            return nil

        case .checkFooter:
            footerBuf[0] = footerBuf[1]
            footerBuf[1] = byte
            bytesNeeded -= 1
            if bytesNeeded != 0 { return nil }

            let checksum = (UInt16(footerBuf[0]) << 8) | UInt16(footerBuf[1])
            state = .waitHeader
            guard checksum == MakeraFraming.frameEnd else {
                packetData.removeAll()
                return nil
            }
            return dispatch()
        }
    }

    private func dispatch() -> MakeraParsedFrame? {
        defer { packetData.removeAll() }
        guard packetData.count >= 5 else { return nil } // length(2)+type(1)+crc(2) minimum

        let crcBytes = Array(packetData.suffix(2))
        let bodyBytes = Array(packetData.dropLast(2)) // length + type + payload
        let calculated = MakeraFraming.crc16(bodyBytes)
        let received = (UInt16(crcBytes[0]) << 8) | UInt16(crcBytes[1])
        guard calculated == received else { return nil }

        let ptype = packetData[2]
        let payload = Data(packetData[3..<(packetData.count - 2)])
        return MakeraParsedFrame(ptype: ptype, payload: payload)
    }
}
