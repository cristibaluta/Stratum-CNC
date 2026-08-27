//
//  ContentView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import AppKit
import SwiftUI

struct CAM_2D_View: NSViewRepresentable {

    @ObservedObject var model: CAMModel

    func makeNSView(context: Context) -> D2_CanvasView {

        let view = D2_CanvasView()
        view.clipsToBounds = true
        view.files = model.files
        view.onAddNew = {
            model.showingFilePicker = true
        }

        return view
    }

    func updateNSView(_ nsView: D2_CanvasView, context: Context) {
        if nsView.files.count != model.files.count {
            nsView.files = model.files
        }
    }
}
