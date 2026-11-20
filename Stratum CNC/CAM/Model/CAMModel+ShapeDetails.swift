//
//  CAMModel+ShapeDetails.swift
//  Stratum CNC
//

import Foundation
import StratumCAM

extension CAMModel {

    /// What the toolpath `id` has selected, one entry per shape and per STEP edge, for the
    /// expandable "Selected" row. Shapes first, in the order they were picked, then the edges.
    /// Empty when the toolpath cuts the whole stock (its selection is ignored).
    func shapeDetails(for id: UUID) -> [ShapeDetail] {
        guard let toolpath = toolpaths.first(where: { $0.id == id }), !toolpath.cutsWholeStock else {
            return []
        }
        let frame = (try? setupFrame(for: toolpath)) ?? .identity

        var details: [ShapeDetail] = []
        for target in toolpath.targets {
            guard let object = canvasState.object(withID: target.objectID),
                  object.paths.indices.contains(target.pathIndex) else {
                continue
            }
            let contours = object.machineContours(forPathAt: target.pathIndex).map(frame.placeFlat)
            details.append(ShapeDetail.describe(contours))
        }
        details += stepWorkspace.shapeDetails(for: toolpath.stepTargets, frame: frame)
        return details
    }
}
