//
//  CAMModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation
import CoreGraphics
import UniformTypeIdentifiers

@MainActor
class CAMModel: ObservableObject {

    // ---- PERSISTENT DATA (mirrors ProjectData) ----
    @Published var selectedStockMaterial: StockMaterial {
        didSet {
            onStockChanged?(selectedStockMaterial)
        }
    }

    // ---- TEMPORARY UI STATE (session-only) ----
    @Published var showingFilePicker = false
    @Published var canvasState = D2_CanvasState()

    // ---- TEMPORARY TOOLPATH EDITING ----
    @Published var toolpaths: [ToolpathData] = []
    @Published var selectedToolpathID: UUID?

    // ---- CANVAS VIEWPORT STATE ----
    // Canvas viewport state — not @Published because changes must not trigger SwiftUI redraws
    var canvasPanOffset: CGPoint = .zero
    var canvasZoomScale: CGFloat = 3.0
    var canvasViewportSaved: Bool = false

    let supportedFiles: [UTType] = [.svg, .dxf]

    // ---- CALLBACKS FOR PERSISTENCE ----
    var onStockChanged: ((StockMaterial) -> Void)?
    var onToolpathsChanged: (([ToolpathData]) -> Void)?

    init(selectedStockMaterial: StockMaterial, toolpaths: [ToolpathData]) {
        self.selectedStockMaterial = selectedStockMaterial
        self.toolpaths = toolpaths
    }

    func loadAndParseFileAt(_ url: URL) {

        let ext = url.pathExtension

        switch ext.lowercased() {
            case "svg":
                if let obj = SVGImporter().parse(url: url) {
                    canvasState.add(obj, select: false)
                }
            case "dxf":
                if let obj = DXFImporter().parse(url: url) {
                    canvasState.add(obj, select: false)
                }
            case "step":
                print("import step")
            default:
                print("Unsupported file type: \(ext)")
        }
    }

    func clear() {
        canvasState.removeAll()
        toolpaths.removeAll()
    }
}
