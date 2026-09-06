//
//  SVGImporter.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 06/09/2026.
//

import Foundation
import PocketSVG

class SVGImporter: Importer {

    private let factory = ObjectFactory()

    func parse(url: URL) -> D2_Object? {

        let svg = SVGLayer(contentsOf: url)
        print(svg.viewBox)
        print(svg.paths)
        print(svg.attributeKeys)

        var bezierPaths: [STBezierPath] = []
        let svgPaths: [SVGBezierPath] = svg.paths
        for path in svgPaths {
//            print(path.svgAttributes)
//            print(path.svgAttributes["transform"] as Any)
            // Some svgs (saved by Inkscape) do not have the real values that will match the viewbox
            // But they contain a transform we can use to scale everything down
            if let cg = path.svgAttributes["transform"] as? CGAffineTransform {
                let p = path
                let nsTransform = AffineTransform(
                    m11: cg.a,
                    m12: cg.b,
                    m21: cg.c,
                    m22: cg.d,
                    tX: cg.tx,
                    tY: cg.ty
                )
                p.transform(using: nsTransform)
                bezierPaths.append(p)
            } else {
                bezierPaths.append(path)
            }
        }

        #if os(macOS)
        // SVG coordinate system starts from top-left
        // Mac coordinate system starts from bottom-left
        // We need to flip all the y values of the bezierPaths while maintaining the viewbox
        let flippedPaths = bezierPaths.map { $0.pathWithFlippedY(inHeight: svg.viewBox.height) }
        bezierPaths = flippedPaths
        #endif

        if let object = factory.makeObject(name: url.lastPathComponent, paths: bezierPaths) {
            return object
        }
        return nil
    }
}
