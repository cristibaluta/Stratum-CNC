//
//  PathSelection.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import Foundation

final class D2_CanvasState: Equatable {

    static func == (lhs: borrowing D2_CanvasState, rhs: borrowing D2_CanvasState) -> Bool {
        lhs.objects.count == rhs.objects.count &&
        lhs.selectedObjectIDs.count == rhs.selectedObjectIDs.count &&
        lhs.selectedPaths.count == rhs.selectedPaths.count &&
        lhs.isStockVisible == rhs.isStockVisible &&
        lhs.zoomScale == rhs.zoomScale
    }

    private(set) var objects: [D2_Object] = []
    private(set) var selectedObjectIDs: Set<UUID> = []
    private(set) var selectedPaths: [PathSelection] = []
    var isStockVisible: Bool = true {
        didSet {
            print("Set stock visible: \(isStockVisible)")
        }
    }
    var zoomScale: Double = 1

//    var selectedObject: D2_Object? {
//        guard let id = selectedObjectIDs.first else {
//            return nil
//        }
//
//        return objects.first { $0.id == id }
//    }

    // MARK: Objects

    func add(_ object: D2_Object, select: Bool) {
        objects.append(object)

        if select {
            selectObject(object.id)
        }
    }

    func setObjects(_ objects: [D2_Object]) {
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
        selectedPaths.removeAll()
    }

    /// Replaces the current selection with a single path.
    func selectPath(objectID: UUID, pathIndex: Int) {
        guard objects.contains(where: { $0.id == objectID }) else {
            return
        }

        selectedObjectIDs.removeAll()
        selectedPaths = [PathSelection(objectID: objectID, pathIndex: pathIndex)]
    }

    /// Adds the path to the selection if it isn't already selected, otherwise removes it.
    /// Used for shift/cmd-click multi-select.
    func togglePathSelection(objectID: UUID, pathIndex: Int) {
        guard objects.contains(where: { $0.id == objectID }) else {
            return
        }

        // Multi-selecting paths only makes sense in path-selection mode, so drop any object selection.
        selectedObjectIDs.removeAll()

        let selection = PathSelection(objectID: objectID, pathIndex: pathIndex)
        if selectedPaths.contains(selection) {
            selectedPaths.removeAll(where: { $0 == selection })
        } else {
            selectedPaths.append(selection)
        }
    }

    func clearSelection() {
        selectedObjectIDs.removeAll()
        selectedPaths.removeAll()
    }

    func isObjectSelected(_ object: D2_Object) -> Bool {
        selectedObjectIDs.contains(object.id)
    }

    /// Single-path convenience for call sites still expecting one index (e.g. legacy inspector code).
    func selectedPathIndex(for object: D2_Object) -> Int? {
        selectedPaths.first { $0.objectID == object.id }?.pathIndex
    }

    /// All selected path indices for a given object, for multi-select rendering/inspection.
    func selectedPathIndices(for object: D2_Object) -> Set<Int> {
        Set(selectedPaths.filter { $0.objectID == object.id }.map { $0.pathIndex })
    }

    func isPathSelected(objectID: UUID, pathIndex: Int) -> Bool {
        selectedPaths.contains(PathSelection(objectID: objectID, pathIndex: pathIndex))
    }
}
