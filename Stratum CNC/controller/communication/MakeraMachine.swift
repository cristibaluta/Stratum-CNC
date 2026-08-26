//
//  MakeraMachine.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.08.2026.
//

import Foundation

/// A Carvera machine discovered on the local network.
///
/// The firmware broadcasts a UDP packet every ~1s on port 3333 with the
/// format: "name,ip,port,busy" (busy is "1" or "0").
/// See: Carvera_Controller/carveracontroller/WIFIStream.py -> MachineDetector
struct MakeraMachine: Identifiable, Equatable, Hashable {
    let id: String   // name+ip is stable enough to dedupe on
    let name: String
    let ip: String
    let port: UInt16
    let busy: Bool

    init(name: String, ip: String, port: UInt16, busy: Bool) {
        self.name = name
        self.ip = ip
        self.port = port
        self.busy = busy
        self.id = "\(name)@\(ip)"
    }
}
