//
//  NSScreen+ScaleFactor.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 10.09.2026.
//

import AppKit

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
