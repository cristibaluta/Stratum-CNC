//
//  SetupObjects.swift
//  Stratum CNC
//
//  What a setup includes and where each object sits in it: the setup's own placement when it has
//  one, otherwise the object's global one. This is the one place that rule lives; anything that
//  needs an object's position for a setup (the canvas, toolpath generation) asks here.
//

import Foundation

/// An object as one setup sees it.
struct PlacedObject: Identifiable, Hashable {
    var object: ProjectObject
    /// The placement that applies in the setup: its override, or the object's global transform
    var transform: ObjectTransform
    /// The setup places it itself
    var isOverridden: Bool

    var id: UUID {
        object.id
    }
}

extension CAMModel {

    /// The objects a setup includes, in the order of the project's objects. A setup with no items
    /// of its own includes all of them. Items whose object no longer exists are ignored.
    func placedObjects(in setup: Setup) -> [PlacedObject] {
        projectObjects
            .filter { setup.includes($0.id) }
            .map { object in
                let override = setup.transformOverride(for: object.id)
                return PlacedObject(object: object,
                                    transform: override ?? object.transform,
                                    isOverridden: override != nil)
            }
    }

    /// Where the object sits in the setup; nil when the setup doesn't include it or it doesn't exist.
    func resolvedTransform(of objectID: UUID, in setup: Setup) -> ObjectTransform? {
        placedObjects(in: setup).first { $0.id == objectID }?.transform
    }
}
