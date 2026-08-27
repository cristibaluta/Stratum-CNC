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
        ZStack {
            if model.files.isEmpty {
                emptyView
            } else {
                // TODO: This view should be swapable with other file types, 2D and 3D
                // If possible can be only one view for 2D but a converter will generate the NSBezierPaths from any input file
                CAM_2D_View(model: model)

                HStack {
                    Spacer()
                    toolpathsPanel
                        .frame(width: 500)
                        .padding(16)
                }
            }
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
        .fileImporter(isPresented: $model.showingFilePicker, allowedContentTypes: [.svg], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    model.loadAndParseFileAt(url)
                }

            case .failure(let error):
                print("Failed:", error)
            }
        }
    }

    private var emptyView: some View {
        VStack {
            Spacer()
            Text("No objects added yet!")
                .font(.headline)
                .foregroundColor(.secondary)
            Button("Import SVG") {
                model.showingFilePicker = true
            }
            Spacer()
        }
    }

    var toolpathsPanel: some View {
        GroupBox("TOOLPATHS") {
            ToolpathListView(model: model)
                .frame(maxWidth: .infinity)
        }
    }
}
