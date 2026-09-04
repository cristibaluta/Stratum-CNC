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

    func makeNSView(context: Context) -> D2_CanvasNSView {

        let view = D2_CanvasNSView()
        view.clipsToBounds = true
        view.canvasState = model.canvasState

        return view
    }

    func updateNSView(_ nsView: D2_CanvasNSView, context: Context) {

        if nsView.canvasState != model.canvasState {
            nsView.canvasState = model.canvasState
        }
    }
}
