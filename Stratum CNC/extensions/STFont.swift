//
//  STFont.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 10.11.2026.
//

import Foundation

#if os(macOS)

import AppKit

typealias STFont = NSFont

#else

import UIKit
typealias STFont = UIFont

#endif
