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
                SVGCanvasNSView(svgFile: svgFile)
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

//        print("PATH COUNT:", paths.count)
//
//        for path in paths {
//            let cgPath = path.cgPath
//
//            print(cgPath)
//
//            cgPath.applyWithBlock { elementPointer in
//                let element = elementPointer.pointee
//
//                switch element.type {
//                case .moveToPoint:
//                    print("Move:", element.points[0])
//
//                case .addLineToPoint:
//                    print("Line:", element.points[0])
//
//                case .addQuadCurveToPoint:
//                    print("Quad:",
//                          element.points[0],
//                          element.points[1])
//
//                case .addCurveToPoint:
//                    print(
//                        "Curve:",
//                        element.points[0],
//                        element.points[1],
//                        element.points[2]
//                    )
//
//                case .closeSubpath:
//                    print("Close")
//
//                @unknown default:
//                    break
//                }
//            }
//        }
    }
}
