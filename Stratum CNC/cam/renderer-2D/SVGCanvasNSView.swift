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

    let files: [CAM_File]
    var onAddNew: (() -> Void)?

    func makeNSView(context: Context) -> SVGCanvasView {

        let view = SVGCanvasView()
        view.clipsToBounds = true
        view.files = files
        view.onAddNew = {
            onAddNew?()
        }

        return view
    }

    func updateNSView(_ nsView: SVGCanvasView, context: Context) {
        if nsView.files.count != files.count {
            nsView.files = files
        }
    }
}
