//
//  GCodeModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import SwiftUI
import UniformTypeIdentifiers

@MainActor
class GCodeStore: ObservableObject {

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

    func generateGCode(for toolpath: ToolpathData, canvasState: D2_CanvasState) {
        do {
            let gcode = try ToolpathGCodeBuilder.generate(for: toolpath, canvasState: canvasState)
            document.load(from: gcode)
        } catch {
            print("G-code generation failed: \(error.localizedDescription)")
            // consider surfacing this in the UI, e.g. an @Published var lastError: String?
        }
    }
}
