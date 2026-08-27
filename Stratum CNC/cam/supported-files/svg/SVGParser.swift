//
//  SVGParser.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import Foundation
import PocketSVG

class SVGParser: D2Parser {

    func parseFileAt(_ url: URL) throws -> [STBezierPath] {
        return SVGBezierPath.pathsFromSVG(at: url)
    }
}
