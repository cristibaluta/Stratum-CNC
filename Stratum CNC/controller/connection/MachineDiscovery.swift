//
//  MakeraMachine.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 20.08.2026.
//

import Foundation
import Network

@MainActor
final class MachineDiscovery: ObservableObject {

    @Published private(set) var machines: [MakeraMachine] = [MakeraMachine(name: "Mock Machine", ip: "00.00.00.00", port: 0, busy: false)]
    @Published private(set) var isScanning = false
    @Published var lastError: String?

    /// Port the Carvera firmware broadcasts discovery packets on.
    private let discoveryPort: NWEndpoint.Port = 3333

    private var listener: NWListener?
    /// Keep open connections alive so we keep receiving from each sender.
    private var activeConnections: [NWConnection] = []

    func startScanning() {
        stopScanning()
//        machines = []
        lastError = nil

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        // Don't restrict to .wifi — some people run the Mac on Ethernet
        // while the Carvera is on WiFi, both on the same LAN/subnet.

        do {
            let listener = try NWListener(using: params, on: discoveryPort)

            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isScanning = true
                    case .failed(let error):
                        self?.lastError = "Discovery listener failed: \(error.localizedDescription)"
                        self?.isScanning = false
                    case .cancelled:
                        self?.isScanning = false
                    default:
                        break
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.accept(connection: connection)
                }
            }

            listener.start(queue: .main)
            self.listener = listener
        } catch {
            lastError = "Could not start discovery listener: \(error.localizedDescription)"
        }
    }

    func stopScanning() {
        listener?.cancel()
        listener = nil
        activeConnections.forEach { $0.cancel() }
        activeConnections.removeAll()
        isScanning = false
    }

    // MARK: - Per-sender connection handling

    private func accept(connection: NWConnection) {
        activeConnections.append(connection)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
                case .ready:
                    Task { @MainActor in
                        self?.receiveNext(on: connection)
                    }
                case .failed, .cancelled:
                    Task { @MainActor in
                        self?.activeConnections.removeAll { $0 === connection }
                    }
                default:
                    break
            }
        }
        connection.start(queue: .main)
    }

    private func receiveNext(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, let text = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    self.parseAndStore(text)
                }
            }

            if error == nil {
                // Keep listening for more broadcasts from this same sender.
                Task { @MainActor in
                    self.receiveNext(on: connection)
                }
            }
        }
    }

    // MARK: - Parsing

    private func parseAndStore(_ text: String) {
        // Expected: "MachineName,192.168.1.42,2222,0"
        let fields = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ",")
            .map(String.init)

        guard fields.count >= 4, let port = UInt16(fields[2]) else {
            return
        }

        let machine = MakeraMachine(
            name: fields[0],
            ip: fields[1],
            port: port,
            busy: fields[3] == "1"
        )

        if let idx = machines.firstIndex(where: { $0.id == machine.id }) {
            machines[idx] = machine // refresh busy state etc.
        } else {
            machines.append(machine)
        }
    }
}
