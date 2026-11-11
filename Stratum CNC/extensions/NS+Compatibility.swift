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
typealias STImage = NSImage
typealias STFont = NSFont
typealias STPoint = NSPoint
typealias STPointArray = NSPointArray

extension NSColor {
    static let rampCardBackground = NSColor.controlBackgroundColor
}

#else

import UIKit

typealias STColor = UIColor
typealias STImage = UIImage
typealias STFont = UIFont
typealias STPoint = CGPoint
typealias STPointArray = UnsafeMutablePointer<CGPoint>

extension UIColor {
    static let rampCardBackground = UIColor.secondarySystemBackground
}

#endif
