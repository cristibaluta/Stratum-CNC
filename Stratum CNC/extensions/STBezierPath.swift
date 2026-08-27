//
//  STBezierPath.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 26.08.2026.
//

import Foundation
#if os(macOS)
import AppKit
typealias STBezierPath = NSBezierPath
#else
import UIKit
typealias STBezierPath = UIBezierPath
#endif
