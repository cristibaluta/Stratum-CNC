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

extension MakeraMachine {
    /// A fake machine that's always available to pick from
    /// `MachinesList`/`MachineConnectSheet`, so the UI — connecting,
    /// jogging, probing, the pre-run review, uploading and running a job —
    /// can be exercised without real hardware. `MachineDiscovery` seeds its
    /// list with exactly this value, and `MachineConnection.connect(to:)`
    /// checks `isMock` to route to `MockMachineSimulator` instead of
    /// opening a real socket.
    static let mock = MakeraMachine(name: "Mock Machine", ip: "00.00.00.00", port: 0, busy: false)

    /// The sentinel IP `.mock` uses is never a routable address, so it's
    /// safe as the marker — checked by IP/port rather than `self == .mock`
    /// so it still recognises the entry after `MachineDiscovery` overwrites
    /// `busy` on a refresh (structural `Equatable` would otherwise stop
    /// matching the moment any field differs).
    var isMock: Bool { ip == MakeraMachine.mock.ip && port == MakeraMachine.mock.port }
}
