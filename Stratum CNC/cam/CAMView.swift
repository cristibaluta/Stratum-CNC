//
//  SvgView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

// The main view of the cam screen.
// It holds the model preview and the list of toolpaths
// You can access also the tools and stocks from here

struct CAMView: View {

    @ObservedObject var model: CAMModel

    var body: some View {
        HStack {
            CAM_SVG_View(model: model)
            
            ToolpathListView()
                .frame(width: 500)
//                .background(
//                    RoundedRectangle(cornerRadius: 8)
//                        .fill(.quaternary.opacity(0.45))
//                )
//                .padding(8)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: {
                    model.showingToolsSheet.toggle()
                }) {
                    Label("Tools", systemImage: "pencil.tip.crop.circle.fill")
                }
                .rotationEffect(.degrees(180))

                Button(action: {
                    model.showingStockSheet.toggle()
                }) {
                    Label("Stock", systemImage: "cube")
                }
            }
        }
        .sheet(isPresented: $model.showingToolsSheet) {
            ToolsSheet(store: model.toolStore)
                .frame(width: 800, height: 600)
        }
        .sheet(isPresented: $model.showingStockSheet) {
            StockSheet(store: model.stockStore)
                .frame(width: 800, height: 600)
        }
    }
}
