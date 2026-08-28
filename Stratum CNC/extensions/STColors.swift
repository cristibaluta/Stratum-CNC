//
//  Colors.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import Foundation
#if os(macOS)

import AppKit

typealias STColor = NSColor

extension NSColor {
    static let rampCardBackground = NSColor.controlBackgroundColor
}

#else

import UIKit
typealias STColor = UIColor

extension UIColor {
    static let rampCardBackground = UIColor.secondarySystemBackground
}

#endif
