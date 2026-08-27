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
#else
import UIKit
typealias STColor = UIColor
#endif
