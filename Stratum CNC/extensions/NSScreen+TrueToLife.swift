//
//  NSScreen+ScaleFactor.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 10.09.2026.
//

import Foundation
import CoreGraphics

#if os(macOS)
import AppKit

typealias STWindow = NSWindow

extension NSScreen {

    @MainActor
    func trueToLifeZoomScale(in window: NSWindow?) -> CGFloat {
        // Fetch screen dimensions (in points) and native pixel resolution
        guard let deviceDescription = self.deviceDescription[NSDeviceDescriptionKey.size] as? NSSize,
              let backingScale = window?.backingScaleFactor ?? self.backingScaleFactor as CGFloat? else {
            return 72.0 / 25.4
        }

        // Physical pixels across screen width
        let pixelWidth = deviceDescription.width * backingScale

        // 3. Obtain real physical screen size (in inches) via CGDisplay
        guard let displayID = self.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return 72.0 / 25.4
        }
        let displaySizeMM = CGDisplayScreenSize(displayID) // Size in millimeters

        guard displaySizeMM.width > 0 else {
            return 72.0 / 25.4
        }

        // Real physical Dots (Pixels) Per Inch
        let physicalDPI = (pixelWidth / displaySizeMM.width) * 25.4

        // 4. Points per millimeter on screen
        // pointsPerMM = (Physical DPI / 25.4) / Backing Scale Factor
        let pointsPerMM = (physicalDPI / 25.4) / backingScale

        return pointsPerMM
    }
}
#else
import UIKit

typealias STWindow = UIWindow
#endif

/// How many view points one millimetre of the real display covers.
enum TrueToLife {

    /// 72 points per inch: what a display with no known physical size is assumed to be.
    static let fallbackPointsPerMM: CGFloat = 72.0 / 25.4

    @MainActor
    static func pointsPerMM(in window: STWindow?) -> CGFloat {
        #if os(macOS)
        guard let screen = window?.screen ?? NSScreen.main else {
            return fallbackPointsPerMM
        }
        return screen.trueToLifeZoomScale(in: window)
        #else
        // iOS doesn't expose the physical size of the display. An iPhone is 163 points per
        // inch and an iPad (except the mini) 132, so 1 mm is close to true size, not exact.
        let pointsPerInch: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 132 : 163
        return pointsPerInch / 25.4
        #endif
    }
}
