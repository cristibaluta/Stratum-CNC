//
//  Contour.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 08.09.2026.
//

import SwiftDXF

struct Contour {
    let entities: [DXF.Entity]   // ordered, oriented so each entity's end == next entity's start
    let isClosed: Bool
}
