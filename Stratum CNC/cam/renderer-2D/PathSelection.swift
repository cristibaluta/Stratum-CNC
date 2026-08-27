//
//  PathSelection.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 28.08.2026.
//

import Foundation

// The paths you click in a 2D drawing

struct PathSelection: Hashable {
    let objectID: UUID
    let pathIndex: Int
}
