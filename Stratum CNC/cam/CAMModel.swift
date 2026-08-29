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

    @Published var toolStore = ToolStore()
    @Published var showingToolsSheet: Bool = false

    @Published var stockStore = StockStore()
    @Published var showingStockSheet: Bool = false

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
    @Published var files: [CAM_File] = []
    /// Persistent CAM objects derived from imported files. Mutations (position, rotation, scale)
    /// made in the canvas are kept here since CAM_Object is a reference type.
    @Published var objects: [CAM_Object] = []
    @Published var toolpaths: [ToolpathData] = []

    private let factory = CAM_ObjectFactory()

    func loadAndParseFileAt(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            print("Could not access:", url)
            return
        }
        defer {
            url.stopAccessingSecurityScopedResource()
        }

        print("URL:", url)

        let svg = SVGImageView(contentsOf: url)
        print(svg.viewBox)
        print(svg.paths)

        var paths = svg.paths as [NSBezierPath]

        #if os(macOS)
        // SVG coordinate system starts from top-left
        // Mac coordinate system starts from bottom-left
        // We need to flip all the y values from the bezierPaths
        let flippedPaths = paths.map { pathWithFlippedY($0, svgHeight: svg.viewBox.height) }
        paths = flippedPaths
        #endif

        let file = CAM_File(url: url, paths: paths)
        files.append(file)
        if let object = factory.makeObject(name: url.lastPathComponent, paths: paths) {
            objects.append(object)
        }
        toolpaths = demoToolpaths
    }

    func pathWithFlippedY(_ path: NSBezierPath, svgHeight: CGFloat) -> NSBezierPath {
        let newPath = NSBezierPath()
        var points = [NSPoint](repeating: .zero, count: 3)

        for i in 0..<path.elementCount {
            let type = path.element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo:
                newPath.move(to: NSPoint(x: points[0].x, y: svgHeight - points[0].y))
            case .lineTo:
                newPath.line(to: NSPoint(x: points[0].x, y: svgHeight - points[0].y))
            case .curveTo:
                newPath.curve(
                    to: NSPoint(x: points[2].x, y: svgHeight - points[2].y),
                    controlPoint1: NSPoint(x: points[0].x, y: svgHeight - points[0].y),
                    controlPoint2: NSPoint(x: points[1].x, y: svgHeight - points[1].y)
                )
            case .closePath:
                newPath.close()
            default:
                break
            }
        }
        return newPath
    }

    let demoToolpaths: [ToolpathData] = [
        ToolpathData(
            name: "Aluminum Inside Pocket",
            tool: Tool(name: "3.175*12mm", shankDiameter: 3.175, toolDiameter: 3.175, length: 12, type: .endMill),
            startZ: 0.0,
            endZ: -3.0,
            contour: .inside,
            ramping: RampingSettings(
                enabled: true,
                type: .helix,
                angle: 3.0,
                length: 5.0
            ),
            feedRate: 500,
            plungeRate: 200,
            spindleRPM: 12000,
            stepDown: 0.5,
            stepOver: 0.4,
            safeZ: 5.0
        ),

        ToolpathData(
            name: "Hardwood Outside Contour",
            tool: Tool(name: "3.175*12mm", shankDiameter: 3.175, toolDiameter: 3.175, length: 12, type: .endMill),
            startZ: 0.0,
            endZ: -6.0,
            contour: .outside,
            ramping: RampingSettings(
                enabled: true,
                type: .linear,
                angle: 5.0,
                length: 10.0
            ),
            feedRate: 1000,
            plungeRate: 300,
            spindleRPM: 10000,
            stepDown: 1.0,
            stepOver: 0.8,
            safeZ: 5.0
        ),

        ToolpathData(
            name: "Plastic Outline",
            tool: Tool(name: "3.175*12mm", shankDiameter: 3.175, toolDiameter: 3.175, length: 12, type: .endMill),
            startZ: 0.0,
            endZ: -4.0,
            contour: .outline,
            ramping: RampingSettings(
                enabled: false,
                type: .none,
                angle: 0,
                length: 0
            ),
            feedRate: 800,
            plungeRate: 250,
            spindleRPM: 10000,
            stepDown: 0.75,
            stepOver: 0.5,
            safeZ: 3.0
        )
    ]
}
