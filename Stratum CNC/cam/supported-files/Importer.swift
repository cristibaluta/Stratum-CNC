//
//  Importer.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 06/09/2026.
//

import Foundation

protocol Importer {
    func parse(url: URL) -> D2_Object?
}
