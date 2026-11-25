//
//  ProjectObject.swift
//  Stratum CNC
//
//  The objects of the project as one list. Today they live in two places: the 2D shapes in
//  `D2_CanvasState.objects` and the STEP bodies in `STEPWorkspace`. This is a read-only view over
//  both, so the Objects panel, and later the setups, can ask "what objects are there and where do
//  they sit" without knowing which is which. It stores nothing: edits still go through the canvas
//  state and the workspace, which is what the project saves from.
//

import Foundation

struct ProjectObject: Identifiable, Hashable {

    enum Kind: Hashable {
        /// A DXF, SVG or Gerber shape (a `D2_Object`)
        case shape
        /// One body of a STEP file (a row of `STEPWorkspace.modelEntries`)
        case stepBody
        /// The alignment pins: built from parameters, not placed by hand
        case fixture
    }

    /// The `D2_Object`'s id (saved with its asset), or the STEP model's row id (derived from the file's
    /// import id and the body's `stateKey`). Both are the same after the project is opened again.
    let id: UUID
    var name: String
    var kind: Kind
    /// The file it was imported from; nil for the alignment pins
    var sourceName: String?
    var transform: ObjectTransform
    var isVisible: Bool

    /// Can be moved, scaled and turned by hand
    var isPlaceable: Bool {
        kind != .fixture
    }
}

extension CAMModel {

    /// Every object of the project, shapes first, then STEP bodies in the order of their files.
    /// A STEP file that has not loaded yet is left out: it has no body to place.
    var projectObjects: [ProjectObject] {
        var result: [ProjectObject] = canvasState.objects.map { object in
            ProjectObject(id: object.id,
                          name: object.name,
                          kind: object.isParametric ? .fixture : .shape,
                          sourceName: object.sourceAssetName,
                          transform: object.transform,
                          isVisible: object.isVisible)
        }
        for entry in stepWorkspace.modelEntries {
            guard let body = entry.body, let scene = stepWorkspace.scene(ofModel: entry.id) else {
                continue
            }
            let position = stepWorkspace.position(of: entry.id)
            let transform = ObjectTransform(x: Double(position.x),
                                            y: Double(position.y),
                                            z: Double(position.z),
                                            scale: Double(scene.content.scale(of: body)),
                                            rotation: 0,
                                            face: scene.content.orientation(of: body))
            result.append(ProjectObject(id: entry.id,
                                        name: entry.name,
                                        kind: .stepBody,
                                        sourceName: stepWorkspace.sources.first { $0.id == entry.sourceID }?.name,
                                        transform: transform,
                                        isVisible: stepWorkspace.isVisible(model: entry.id)))
        }
        return result
    }

    /// One object by id (a shape's or a STEP model's).
    func projectObject(withID id: UUID) -> ProjectObject? {
        projectObjects.first { $0.id == id }
    }
}
