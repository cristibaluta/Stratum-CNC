//
//  CAMModel.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import Foundation
import CoreGraphics
import Combine
import UniformTypeIdentifiers

@MainActor
class CAMModel: ObservableObject {

    // ---- PERSISTENT DATA (mirrors ProjectData) ----
    @Published var selectedStockMaterial: StockMaterial {
        didSet {
            canvasState.stock = selectedStockMaterial
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
    // Persisted between sessions. Not @Published: this is *reported* by the
    // canvas (via CAM_2D_View's onViewportChanged) after the user pans/zooms,
    // it never drives a SwiftUI redraw itself — that would fight the canvas's
    // own viewport handling (see CAM_2D_View.updateNSView).
    private(set) var canvasPanOffset: CGPoint = .zero
    private(set) var canvasZoomScale: CGFloat = 3.0
    private(set) var canvasViewportSaved: Bool = false

    var savedViewport: (panOffset: CGPoint, zoomScale: CGFloat)? {
        canvasViewportSaved ? (canvasPanOffset, canvasZoomScale) : nil
    }

    func saveViewport(panOffset: CGPoint, zoomScale: CGFloat) {
        canvasPanOffset = panOffset
        canvasZoomScale = zoomScale
        canvasViewportSaved = true
    }

    let supportedFiles: [UTType] = [.svg, .dxf, .init(filenameExtension: "step")!, .init(filenameExtension: "stp")!]

    // ---- CALLBACKS FOR PERSISTENCE ----
    var onStockChanged: ((StockMaterial) -> Void)?
    var onToolpathsChanged: (([ToolpathData]) -> Void)?

    private var cancellables = Set<AnyCancellable>()

    init(selectedStockMaterial: StockMaterial, toolpaths: [ToolpathData]) {
        self.selectedStockMaterial = selectedStockMaterial
        self.toolpaths = toolpaths
        self.canvasState.stock = selectedStockMaterial

        // D2_CanvasState is an ObservableObject nested inside a @Published
        // property. SwiftUI does NOT forward its objectWillChange up through
        // CAMModel automatically — that's a well-known Combine/SwiftUI gap.
        // Without this line, selecting/editing objects through canvasState
        // would repaint the canvas (which observes canvasState directly) but
        // leave CAMView's body — the inspector, the objects list — stale,
        // since CAMView only observes camModel. This forwards it explicitly.
        canvasState.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
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
            case "step", "stp":
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
