//
//  UTType+DXF.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 07/09/2026.
//

import UniformTypeIdentifiers

extension UTType {
    static let dxf = UTType(
        importedAs: "com.autodesk.dxf",
        conformingTo: .data
    )
}
