//
//  SVGImporter.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 06/09/2026.
//

import Foundation
import PocketSVG
import StratumCAM

class SVGImporter: Importer {

    private let factory = ObjectFactory()

    func parse(url: URL) -> D2_Object? {

        // PocketSVG ignores <use>/<defs> and group transforms; flatten first.
        let source = SVGFlattener.flattenedURLIfNeeded(for: url)
        defer {
            if source != url {
                try? FileManager.default.removeItem(at: source)
            }
        }

        let svg = SVGLayer(contentsOf: source)
        if svg.paths.isEmpty {
            print("SVGImporter: no paths found in \(url.lastPathComponent) (viewBox \(svg.viewBox))")
        }

        var bezierPaths: [STBezierPath] = []
        let svgPaths: [SVGBezierPath] = svg.paths
        for path in svgPaths {
//            print(path.svgAttributes)
//            print(path.svgAttributes["transform"] as Any)
            // Some svgs (saved by Inkscape) do not have the real values that will match the viewbox
            // But they contain a transform we can use to scale everything down
            if let cg = path.svgAttributes["transform"] as? CGAffineTransform {
                let nsTransform = AffineTransform(
                    m11: cg.a,
                    m12: cg.b,
                    m21: cg.c,
                    m22: cg.d,
                    tX: cg.tx,
                    tY: cg.ty
                )
                path.transform(using: nsTransform)
            }
            bezierPaths.append(path)
        }

        #if os(macOS)
        // SVG coordinate system starts from top-left
        // Mac coordinate system starts from bottom-left
        // We need to flip all the y values of the bezierPaths while maintaining the viewbox
        bezierPaths = bezierPaths.map { $0.pathWithFlippedY(inHeight: svg.viewBox.height) }
        #endif

        // One path per subpath, like the DXF and Gerber importers (one path per
        // contour). A single SVG <path> can hold many subpaths — the outline
        // and the cut-outs of a shape, the rings of an "O" — and keeping them
        // in one `paths[i]` made them select and pick as a single unit.
        // Split after the Y-flip so the pieces keep the flipped orientation.
        // To machine an outline together with its holes, pick them all.
        var paths: [STBezierPath] = []
        // Index-aligned with `paths` — see D2_Object.contours
        var contours: [[SC.Contour]] = []
        for subpath in bezierPaths.flatMap({ $0.subpaths() }) {
            let subpathContours = subpath.dxfContours()
            // Nothing machinable (e.g. a zero-length segment): skip it so
            // `paths` and `contours` stay aligned and nothing selectable is empty.
            guard !subpathContours.isEmpty else {
                continue
            }
            paths.append(subpath)
            contours.append(subpathContours)
        }

        // Derive entities from the final, already-flipped paths so `entities`
        // describes the exact same orientation as `paths` — computing them
        // beforehand (from pre-flip geometry) would leave entities mirrored
        // vertically relative to what's actually drawn.
        let entities = paths.flatMap { $0.dxfEntities() }

        return factory.makeObject(name: url.lastPathComponent, paths: paths, entities: entities, contours: contours)
    }
}
