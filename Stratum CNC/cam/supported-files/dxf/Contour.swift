//
//  Contour.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 08.09.2026.
//

import SwiftDXF

struct Contour {
    struct Chained {
        let entity: DXF.Entity
        let reversed: Bool   // true if this entity is walked from its "b" endpoint to its "a" endpoint
    }
    let entities: [Chained]
    let isClosed: Bool
}
