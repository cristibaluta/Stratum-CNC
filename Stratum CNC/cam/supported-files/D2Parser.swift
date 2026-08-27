//
//  D2Parser.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import Foundation

protocol D2Parser {
    func parseFileAt(_ url: URL) throws -> [STBezierPath]
}
