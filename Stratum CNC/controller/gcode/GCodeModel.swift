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


    func generateGCode(svgPaths: [NSBezierPath]) {
        let subpaths = BezierPathFlattener.flatten(svgPaths, tolerance: 0.05) // mm

        let gcode = GCodeGenerator.generate(
            subpaths: subpaths,
            units: .millimeters,
            safeHeightZ: 5.0,
            cutDepthZ: -2.0,
            feedRateCut: 900,
            feedRatePlunge: 150,
            spindleSpeed: 15000
        )

        print(gcode)
        document.load(from: gcode)
    }

}
