//
//  ProjectPreviewRenderer.swift
//  Stratum CNC
//
//  Draws the objects on the CAM canvas into the PNG a project card shows (`preview.png`).
//  It uses the same world-space outlines the canvas draws (`D2_RenderObjectBuilder`), so the
//  picture is what is on screen: every visible object at its current position, size and
//  rotation. Pure CoreGraphics, so it needs neither the Metal view nor a window.
//

import AppKit
import CoreGraphics

enum ProjectPreviewRenderer {

    /// A fixed rectangle (3:2), whatever the shape of the objects: the card shows it as it is.
    static let imageSize = CGSize(width: 900, height: 600)

    /// Empty border around the drawing, as a fraction of the shorter side.
    private static let marginFraction: CGFloat = 0.12

    /// Opaque black on a transparent background: only the alpha matters. The project card
    /// shows the picture as a template image in the text color (see `ProjectPreview`), so
    /// the drawing is dark in light mode and light in dark mode.
    private static let stroke = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

    /// The PNG of `objects`, scaled to fit and centered, or nil when there is nothing to draw.
    /// Hidden objects are left out unless `ignoringVisibility`, which is for an object the user
    /// picked by name.
    static func pngData(for objects: [D2_Object], ignoringVisibility: Bool = false) -> Data? {
        let paths = objects
            .filter { ignoringVisibility || $0.isVisible }
            .flatMap { object in
                D2_RenderObjectBuilder.renderPaths(for: object,
                                                   objectSelected: false,
                                                   selectedPathIndexes: [],
                                                   pickedPathIndexes: [])
            }
            .filter { !$0.worldBounds.isNull && !$0.worldBounds.isInfinite }
        guard let first = paths.first else {
            return nil
        }
        var bounds = paths.dropFirst().reduce(first.worldBounds) { $0.union($1.worldBounds) }

        // A single line has no width or height; give it some so the scale stays finite
        let minimumExtent: CGFloat = 1
        if bounds.width < minimumExtent {
            bounds = bounds.insetBy(dx: (bounds.width - minimumExtent) / 2, dy: 0)
        }
        if bounds.height < minimumExtent {
            bounds = bounds.insetBy(dx: 0, dy: (bounds.height - minimumExtent) / 2)
        }

        let width = Int(imageSize.width)
        let height = Int(imageSize.height)
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }

        // The bitmap starts fully transparent; only the outlines are drawn.
        // Fit the drawing in the image minus the margin and put its middle in the image's middle.
        // World space is y-up like the bitmap, so there is no flip.
        let margin = min(imageSize.width, imageSize.height) * marginFraction
        let scale = min((imageSize.width - 2 * margin) / bounds.width,
                        (imageSize.height - 2 * margin) / bounds.height)
        context.translateBy(x: imageSize.width / 2, y: imageSize.height / 2)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.midX, y: -bounds.midY)

        context.setStrokeColor(stroke)
        // A line the same thickness in the picture whatever the scale
        context.setLineWidth(2.5 / scale)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        for path in paths {
            context.addPath(path.worldPath)
            context.strokePath()
        }

        guard let image = context.makeImage() else {
            return nil
        }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
