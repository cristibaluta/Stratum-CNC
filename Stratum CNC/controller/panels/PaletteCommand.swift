//
//  PaletteCommand.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 19.08.2026.
//

import SwiftUI
import StratumLink

struct PaletteCommand: Identifiable {
    let id = UUID()
    let title: String
    let command: SL.Command?
    let rawCommand: String

    init(title: String, command: SL.Command) {
        self.title = title
        self.command = command
        self.rawCommand = command.command
    }

    init(title: String, rawCommand: String) {
        self.title = title
        self.command = nil
        self.rawCommand = rawCommand
    }
}
