//
//  PathSelection.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import Foundation

struct SVGPathSelection: Equatable {
    let objectID: UUID
    let pathIndex: Int
}

final class SVGCanvasState {

    private(set) var objects: [CAM_Object] = []
    private(set) var selectedObjectIDs: Set<UUID> = []
    private(set) var selectedPath: SVGPathSelection?

    var selectedObject: CAM_Object? {
        guard let id = selectedObjectIDs.first else {
            return nil
        }

        return objects.first { $0.id == id }
    }

    // MARK: Objects

    func add(_ object: CAM_Object, select: Bool) {
        objects.append(object)

        if select {
            selectObject(object.id)
        }
    }

    func setObjects(_ objects: [CAM_Object]) {
        self.objects = objects
    }

    func removeAll() {
        objects.removeAll()
        clearSelection()
    }

    // MARK: Selection

    func selectObject(_ id: UUID) {
        guard objects.contains(where: { $0.id == id }) else {
            return
        }

        selectedObjectIDs = [id]
        selectedPath = nil
    }

    func selectPath(objectID: UUID, pathIndex: Int) {
        guard objects.contains(where: { $0.id == objectID }) else {
            return
        }

        selectedObjectIDs.removeAll()
        selectedPath = SVGPathSelection(objectID: objectID, pathIndex: pathIndex)
    }

    func clearSelection() {
        selectedObjectIDs.removeAll()
        selectedPath = nil
    }

    func isObjectSelected(_ object: CAM_Object) -> Bool {
        selectedObjectIDs.contains(object.id)
    }

    func selectedPathIndex(for object: CAM_Object) -> Int? {
        guard selectedPath?.objectID == object.id else {
            return nil
        }

        return selectedPath?.pathIndex
    }
}
