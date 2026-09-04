//
//  CAMModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation
import PocketSVG

@MainActor
class CAMModel: ObservableObject {

    @Published var selectedStockMaterial = StockMaterial(
        name: "Workpiece",
        material: .aluminum,
        geometry: .rectangular(width: 100, height: 50, depth: 10)
    )

    // Canvas viewport state — not @Published because changes must not trigger SwiftUI redraws
    var canvasPanOffset: CGPoint = .zero
    var canvasZoomScale: CGFloat = 3.0
    /// True once the user has panned/zoomed or the auto-fit has run at least once.
    var canvasViewportSaved: Bool = false

    // Insert new files. temporary vars to use
    @Published var showingFilePicker = false

    /// Persistent CAM objects derived from imported files.
    /// Mutations (position, rotation, scale) made in the canvas are kept here since CAM_Object is a reference type.
    @Published var objects: [D2_Object] = []
    @Published var toolpaths: [ToolpathData] = []
    @Published var canvasState = D2_CanvasState()

    private let factory = ObjectFactory()

    func loadAndParseFileAt(_ url: URL) {

        let svg = SVGImageView(contentsOf: url)
        print(svg.viewBox)
        print(svg.paths)

        var bezierPaths = svg.paths as [STBezierPath]

        #if os(macOS)
        // SVG coordinate system starts from top-left
        // Mac coordinate system starts from bottom-left
        // We need to flip all the y values of the bezierPaths while maintaining the viewbox
        let flippedPaths = bezierPaths.map { $0.pathWithFlippedY(inHeight: svg.viewBox.height) }
        bezierPaths = flippedPaths
        #endif

        if let object = factory.makeObject(name: url.lastPathComponent, paths: bezierPaths) {
            objects.append(object)
        }
    }

    func clear() {
        objects.removeAll()
        toolpaths.removeAll()
    }
}
