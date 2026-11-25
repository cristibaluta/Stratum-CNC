//
//  SetupPlacement.swift
//  Stratum CNC
//
//  Puts the active setup's placement on the canvas, and sends edits to the right place.
//
//  The 2D canvas has one position per object, and the project file saves that one as the object's
//  global placement. A setup can place an object itself (`SetupItem.transformOverride`), so the
//  canvas shows the override while that setup is active:
//
//   - `applyActivePlacement` moves the objects to the active setup's placement. The global one of an
//     object shown at an override is kept in `globalPlacementShadow` meanwhile.
//   - An edit (panel or canvas drag) of an object the setup places itself changes the override.
//     An edit of any other object changes the global placement, as before.
//   - What goes to the project file is always the global placement (`withGlobalPlacement`).
//
//  STEP bodies are not covered yet: they keep their own state in `STEPWorkspace`.
//

import Foundation
import StratumCAM
import SwiftSTEP

extension ObjectTransform {

    /// Equal within what a round trip through width and scale can lose.
    func isClose(to other: ObjectTransform) -> Bool {
        face == other.face
            && abs(x - other.x) < 1e-6
            && abs(y - other.y) < 1e-6
            && abs(z - other.z) < 1e-6
            && abs(scale - other.scale) < 1e-6
            && abs(rotation - other.rotation) < 1e-6
    }
}

extension CAMModel {

    private var activeSetup: Setup? {
        setups.first { $0.id == activeSetupID }
    }

    /// The 2D objects the active setup can place by itself (not the parametric ones).
    private var placeableObjects: [D2_Object] {
        canvasState.objects.filter { !$0.isParametric }
    }

    /// Shows the active setup's placement: its override for the objects that have one, the global
    /// placement for the rest. Results built at another placement are outdated by a move.
    func applyActivePlacement() {
        guard let setup = activeSetup else {
            return
        }
        var moved = false
        var membershipChanged = false
        // Objects the setup doesn't include drop off the canvas (and out of picking). The fixtures
        // are in the setups that use them: those on the stock they are attached to.
        for object in canvasState.objects {
            let included = object.isParametric
                ? (setup.usesFixtures && object.fixtureStockID == projectStock(for: setup).id)
                : setup.includes(object.id)
            if object.isInActiveSetup != included {
                object.isInActiveSetup = included
                membershipChanged = true
            }
        }
        if membershipChanged {
            canvasState.objectWillChange.send()
        }
        for object in placeableObjects {
            if let override = setup.transformOverride(for: object.id) {
                if globalPlacementShadow[object.id] == nil {
                    // Not shown at an override yet: what the canvas holds is the global placement
                    globalPlacementShadow[object.id] = object.transform
                }
                if !object.transform.isClose(to: override) {
                    object.transform = override
                    moved = true
                }
            } else if let global = globalPlacementShadow.removeValue(forKey: object.id) {
                object.transform = global
                moved = true
            }
        }
        // STEP bodies the setup doesn't include are taken off the canvas too
        var excluded: [UUID: Set<STEP.BodyID>] = [:]
        for entry in stepWorkspace.modelEntries {
            if let body = entry.body, !setup.includes(entry.id) {
                excluded[entry.sourceID, default: []].insert(body)
            }
        }
        for (sourceID, scene) in stepWorkspace.documents {
            scene.setExcludedBodies(excluded[sourceID] ?? [])
        }
        if moved {
            canvasState.objectWillChange.send()
            discardGenerations()
        }
    }

    /// Called after an edit on the canvas: an object the active setup places itself, and that now
    /// sits elsewhere, was edited in this setup, so its override takes the new placement.
    func routeCanvasEditToActiveSetup() {
        guard let setup = activeSetup else {
            return
        }
        for object in placeableObjects {
            guard let override = setup.transformOverride(for: object.id) else {
                continue
            }
            let shown = object.transform
            if !shown.isClose(to: override) {
                setTransformOverride(shown, for: object.id, inSetup: setup.id)
            }
        }
    }

    /// Runs `body` with the objects at their global placement, then puts the setup's back.
    func withGlobalPlacement(_ body: () -> Void) {
        guard !globalPlacementShadow.isEmpty else {
            body()
            return
        }
        let shown = globalPlacementShadow.keys.compactMap { id in
            canvasState.object(withID: id).map { ($0, $0.transform) }
        }
        for (object, _) in shown {
            if let global = globalPlacementShadow[object.id] {
                object.transform = global
            }
        }
        body()
        for (object, transform) in shown {
            object.transform = transform
        }
    }

    /// Whether the active setup places the object itself.
    func hasPlacementOverride(_ objectID: UUID) -> Bool {
        activeSetup?.transformOverride(for: objectID) != nil
    }

    /// "This setup only" on, or "Reset to global" off, for a 2D object in the active setup.
    func setPlacementOverride(_ enabled: Bool, for objectID: UUID) {
        guard let setup = activeSetup, let object = canvasState.object(withID: objectID),
              !object.isParametric else {
            return
        }
        if enabled {
            guard setup.transformOverride(for: objectID) == nil else {
                return
            }
            if !setup.includes(objectID) || setup.items.isEmpty {
                // A setup without items includes everything: list the objects so one can be placed
                var ids = setup.items.isEmpty ? projectObjects.map(\.id) : setup.items.map(\.objectID)
                if !ids.contains(objectID) {
                    ids.append(objectID)
                }
                setSetupObjects(setup.id, to: ids)
            }
            // What the canvas shows is the global placement: it becomes this setup's, to edit apart
            setTransformOverride(object.transform, for: objectID, inSetup: setup.id)
        } else {
            setTransformOverride(nil, for: objectID, inSetup: setup.id)
        }
    }
}
