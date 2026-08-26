//
//  ContentView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PocketSVG

struct CAM_SVG_View: View {

    @ObservedObject var model: CAMModel
    
    var body: some View {
        VStack {
            Button("Import SVG") {
                model.showingFilePicker = true
            }
            if let svgFile = model.svgFile {
                SVGCanvasNSView(svgFile: svgFile, onAddNew: {
                    model.showingFilePicker = true
                })
            }
        }
        .fileImporter(isPresented: $model.showingFilePicker, allowedContentTypes: [.svg], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    loadAndParseSVG(url)
                }

            case .failure(let error):
                print("Failed:", error)
            }
        }
    }

    private func loadAndParseSVG(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            print("Could not access:", url)
            return
        }

        defer {
            url.stopAccessingSecurityScopedResource()
        }

        print("URL:", url)

        let paths = SVGBezierPath.pathsFromSVG(at: url)
        model.svgFile = SVGFile(url: url, paths: paths)
    }
}
