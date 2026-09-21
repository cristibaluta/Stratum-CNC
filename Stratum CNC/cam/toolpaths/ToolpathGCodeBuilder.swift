//
//  ToolpathGCodeBuilder.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 08.09.2026.
//


import AppKit

enum ToolpathGCodeBuilder {

    enum BuildError: Error, LocalizedError {
        case noTarget
        case objectNotFound
        case pathIndexOutOfRange
        case emptyPath

        var errorDescription: String? {
            switch self {
            case .noTarget: return "This toolpath has no shapes yet — use 'Select shapes' and click them on the canvas."
            case .objectNotFound: return "The object this toolpath targets is no longer on the canvas."
            case .pathIndexOutOfRange: return "The targeted contour no longer exists on this object (was the file re-imported?)."
            case .emptyPath: return "The targeted contour has no drawable geometry."
            }
        }
    }

    /// Builds a complete G-code program for one toolpath, using the contours
    /// it targets (`toolpath.targets`), resolved against the current canvas state.
    static func generate(for toolpath: ToolpathData, canvasState: D2_CanvasState, flattenTolerance: CGFloat = 0.05) throws -> String {

        guard !toolpath.targets.isEmpty else {
            throw BuildError.noTarget
        }

        return ""
    }
}
