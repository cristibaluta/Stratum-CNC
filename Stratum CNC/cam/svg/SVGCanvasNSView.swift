//
//  SVGCanvas.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI
import AppKit

// NSView wrapper to drop into SwiftUI

struct SVGCanvasNSView: NSViewRepresentable {

    let svgFile: SVGFile

    func makeNSView(context: Context) -> SVGCanvasView {

        let view = SVGCanvasView()
        view.insertSvgFile(svgFile)
        view.clipsToBounds = true

        return view
    }

    func updateNSView(_ nsView: SVGCanvasView, context: Context) {
        if nsView.currentPathCount != svgFile.paths.count {
            nsView.insertSvgFile(svgFile)
        }
    }
}
