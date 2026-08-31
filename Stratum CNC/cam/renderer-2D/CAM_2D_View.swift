//
//  ContentView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import AppKit
import SwiftUI

struct CAM_2D_View: NSViewRepresentable {

    @ObservedObject var model: CAMStore

    func makeNSView(context: Context) -> D2_CanvasNSView {

        let view = D2_CanvasNSView()
        view.clipsToBounds = true
        view.objects = model.objects
        view.stockMaterial = model.selectedStockMaterial
        view.onAddNew = {
            model.showingFilePicker = true
        }

        return view
    }

    func updateNSView(_ nsView: D2_CanvasNSView, context: Context) {
        if nsView.objects.count != model.objects.count {
            nsView.objects = model.objects
        }
        if nsView.stockMaterial != model.selectedStockMaterial {
            nsView.stockMaterial = model.selectedStockMaterial
        }
    }
}
