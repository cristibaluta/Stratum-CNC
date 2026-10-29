//
//  ToolbarTexture.swift
//  Stratum CNC
//
//  A small tiled texture for the toolbar background: the accent colour with fine diagonal
//  hatching, so the bar reads as a surface of its own over the canvas.
//

import SwiftUI
import AppKit

enum ToolbarTexture {

    /// The tile as a SwiftUI paint, to be used with `.toolbarBackground`.
    static var paint: ImagePaint {
        ImagePaint(image: Image(nsImage: tile), scale: 2)
    }

    private static let tile: NSImage = {
        let size = NSSize(width: 8, height: 8)
        // Drawn on demand, so the accent colour and appearance (light / dark) are current.
        return NSImage(size: size, flipped: false) { rect in
            NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
            rect.fill()

            let lines = NSBezierPath()
            // Diagonal lines that wrap around the tile edges so it repeats without seams.
            for offset in stride(from: -8.0, through: 8.0, by: 8.0) {
                lines.move(to: NSPoint(x: offset, y: 0))
                lines.line(to: NSPoint(x: offset + 8, y: 8))
            }
            lines.lineWidth = 1
            NSColor.white.withAlphaComponent(0.12).setStroke()
            lines.stroke()
            return true
        }
    }()
}
