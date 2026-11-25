//
//  ObjectFocus.swift
//  Stratum CNC
//
//  The Objects tree's selection: one focused object (always, once the project has objects) and
//  the active setup. Every object has at least one setup of its own, a Top by default, so
//  selecting an object opens that setup and the canvas shows only what the setup includes.
//

import Foundation

extension CAMModel {

    /// The objects that can have setups: everything but the fixtures.
    var regularObjectIDs: [UUID] {
        projectObjects.filter { $0.kind != .fixture }.map(\.id)
    }

    /// Gives every object a setup of its own (a Top), and keeps the focus on an object that exists.
    /// Called when the project's objects change (an import, a delete, a project opened). A setup
    /// from before objects had their own, which includes everything, is given the first object
    /// that no setup includes yet.
    func ensureDefaultSetups() {
        let ids = regularObjectIDs
        guard !ids.isEmpty else {
            return
        }
        healSetups(regularIDs: ids)
        let previousActive = activeSetupID
        var owned = Set(setups.flatMap { $0.items.map(\.objectID) })

        for setup in setups where setup.items.isEmpty {
            guard let id = ids.first(where: { !owned.contains($0) }) else {
                continue
            }
            setSetupObjects(setup.id, to: [id])
            owned.insert(id)
        }
        var created: [UUID] = []
        for id in ids where !owned.contains(id) {
            let setupID = addSetup(face: .top)
            setSetupObjects(setupID, to: [id])
            owned.insert(id)
            created.append(id)
        }
        // Adding setups makes them active; the one that was open stays open
        activateSetup(previousActive)
        // An object imported into a project that already had one becomes the selection
        if focusedObjectID != nil, let imported = created.last {
            focusObject(imported, keepingActiveSetup: false)
            if canvasState.object(withID: imported) != nil {
                stepWorkspace.selectedModelID = nil
                canvasState.selectObject(imported)
            } else {
                canvasState.clearSelection()
                stepWorkspace.select(model: imported)
            }
        }
        // What the active setup doesn't include is off the canvas, also for what was just imported
        applyActivePlacement()

        if let focus = focusedObjectID, ids.contains(focus) || canvasState.object(withID: focus) != nil {
            return
        }
        focusObject(ids[0], keepingActiveSetup: false)
    }

    /// Repairs setups saved with object ids that no longer exist (a STEP body used to get a new id
    /// on every launch, so each open added a Top and left the earlier setups without an object):
    /// such a setup goes back under an object, and the empty Tops added by mistake are removed.
    /// Waits until every STEP file has loaded, so a body still loading isn't taken for a missing one.
    private func healSetups(regularIDs ids: [UUID]) {
        guard stepWorkspace.modelEntries.allSatisfy({ $0.body != nil }) else {
            return
        }
        let existing = Set(canvasState.objects.map(\.id)).union(ids)
        let orphans = setups.filter { setup in
            !setup.items.isEmpty && !setup.items.contains { existing.contains($0.objectID) }
        }
        if !orphans.isEmpty {
            let orphanIDs = Set(orphans.map(\.id))
            let ownedByOthers = Set(setups.filter { !orphanIDs.contains($0.id) }.flatMap { $0.items.map(\.objectID) })
            if let target = ids.first(where: { !ownedByOthers.contains($0) }) ?? ids.first {
                for orphan in orphans {
                    setSetupObjects(orphan.id, to: [target])
                }
            }
        }

        // The same object, face and flip twice, and one of them empty: the extra one is a leftover
        var groups: [String: [Setup]] = [:]
        for setup in setups where setup.items.count == 1 {
            // The same face on another stock is a setup of its own, not a leftover
            groups["\(setup.items[0].objectID)|\(setup.angle)|\(setup.axis.rawValue)|\(setup.stockID)", default: []].append(setup)
        }
        var extras: [UUID] = []
        for group in groups.values where group.count > 1 {
            let keep = group.first { !toolpaths(in: $0.id).isEmpty } ?? group[0]
            extras += group.filter { $0.id != keep.id && toolpaths(in: $0.id).isEmpty }.map(\.id)
        }
        for id in extras {
            deleteSetup(id)
        }
    }

    /// Focuses an object. Unless the active setup should stay (a click on the canvas), the object's
    /// own first setup becomes the active one, so the canvas shows that object alone.
    func focusObject(_ id: UUID, keepingActiveSetup: Bool) {
        focusedObjectID = id
        isSetupSelected = false
        let active = setups.first { $0.id == activeSetupID }
        if keepingActiveSetup, let active, active.items.contains(where: { $0.objectID == id }) {
            return
        }
        let own = setups.first { $0.items.count == 1 && $0.items[0].objectID == id }
            ?? setups.first { $0.items.contains { $0.objectID == id } }
        if let own, own.id != activeSetupID {
            activateSetup(own.id)
        }
    }

    /// After another setup became active: the focus follows it, unless it already is one of its objects.
    func syncFocusToActiveSetup() {
        guard let setup = setups.first(where: { $0.id == activeSetupID }), !setup.items.isEmpty else {
            return
        }
        if let focus = focusedObjectID, setup.items.contains(where: { $0.objectID == focus }) {
            return
        }
        focusedObjectID = setup.items[0].objectID
    }
}
