//
//  GCodeModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import SwiftUI
import UniformTypeIdentifiers

@MainActor
class GCodeModel: ObservableObject {

    @Published var document = NCFileDocument()

    @Published var selectedToolpathID: UUID?
    @Published var requestedLine: Int?
    @Published var analyzedLineCount = -1

    var allowedContentTypes: [UTType] {
        var types: [UTType] = [.plainText]
        for ext in ["nc", "ngc", "gcode", "cnc", "tap"] {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }
}
