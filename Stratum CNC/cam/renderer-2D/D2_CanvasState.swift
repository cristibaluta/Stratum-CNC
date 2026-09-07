//
//  D2_CanvasState.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import Foundation
import CoreGraphics

/// Single source of truth for everything the 2D canvas, the objects inspector
/// and the material panel need to agree on: the objects, the current
/// selection, stock visibility/material, and the current zoom level.
///
/// IMPORTANT: nothing outside this class should mutate a `D2_Object`'s
/// properties directly. Every mutation goes through a method here so there's
/// one place to look when something behaves unexpectedly, and — crucially —
/// so we can reliably notify observers. `D2_Object` is a plain (non-Observable)
/// class, so mutating a property on an instance already inside `objects` does
/// NOT trigger `@Published`'s notification by itself; the setters below call
/// `objectWillChange.send()` explicitly to make up for that.
final class D2_CanvasState: ObservableObject, Equatable {

    @Published var objects: [D2_Object] = []
    @Published private(set) var selectedObjectIDs: Set<UUID> = []
    @Published private(set) var selectedPaths: [PathSelection] = []

    /// Whether the stock should be drawn. The persisted value lives in
    /// ProjectData; whoever owns that (currently CAMView) is responsible for
    /// mirroring it here whenever it changes, so the renderer only ever has
    /// one flag to read.
    @Published var isStockVisible: Bool = true

    /// Stock material/geometry to render. Mirrored here from
    /// CAMModel.selectedStockMaterial so the renderer has a single place to
    /// read it from instead of reaching back out to CAMModel.
    @Published var stock: StockMaterial?

    /// The canvas's current zoom scale. Kept in sync by D2_CanvasNSView on
    /// every pan/zoom/fit so anything computing zoom-dependent stroke widths
    /// (stock texture, ruler) reads the value that's actually on screen,
    /// instead of the stale default it used to be stuck at.
    @Published var zoomScale: CGFloat = 1

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

    func removeObject(_ id: UUID) {
        objects.removeAll { $0.id == id }
        selectedObjectIDs.remove(id)
        selectedPaths.removeAll { $0.objectID == id }
    }

    func removeAll() {
        objects.removeAll()
        clearSelection()
    }

    func object(withID id: UUID) -> D2_Object? {
        objects.first { $0.id == id }
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

    // MARK: Object editing
    //
    // These are the ONLY methods that should ever change a D2_Object's
    // geometry — used by both the canvas's own drag handling and the
    // SwiftUI inspector, so there is exactly one code path to reason about.

    /// Used for continuous drag-to-move on the canvas.
    func moveObject(_ id: UUID, to position: CGPoint) {
        guard let object = object(withID: id) else { return }
        objectWillChange.send()
        object.position = position
    }

    /// Used by the inspector's text fields (X, Y, Width, Height, Rotation).
    func setValue(_ value: CGFloat, for property: Property, objectID: UUID) {
        guard let object = object(withID: objectID) else { return }
        objectWillChange.send()
        switch property {
        case .x: object.position.x = value
        case .y: object.position.y = value
        case .width: object.width = max(value, 0.001)
        case .height: object.setHeight(value)
        case .rotation: object.setRotation(value)
        }
    }

    /// Used by the inspector's +1/-1 nudge buttons.
    func nudge(_ objectID: UUID, property: Property, amount: CGFloat) {
        guard let object = object(withID: objectID) else { return }
        objectWillChange.send()
        switch property {
        case .x: object.position.x += amount
        case .y: object.position.y += amount
        default: break
        }
    }

    /// Used by the inspector's ÷2/×2 buttons.
    func scaleWidth(_ objectID: UUID, factor: Int) {
        guard let object = object(withID: objectID), factor != 0 else { return }
        objectWillChange.send()
        object.width = factor > 0
            ? max(object.width * CGFloat(factor), 0.001)
            : max(object.width / CGFloat(-factor), 0.001)
    }

    /// Used by the inspector's -90°/+90° buttons.
    func rotateObject(_ objectID: UUID, by degrees: CGFloat) {
        guard let object = object(withID: objectID) else { return }
        objectWillChange.send()
        object.rotate(by: degrees)
    }

    static func == (lhs: borrowing D2_CanvasState, rhs: borrowing D2_CanvasState) -> Bool {
        lhs.objects.count == rhs.objects.count &&
        lhs.selectedObjectIDs.count == rhs.selectedObjectIDs.count &&
        lhs.selectedPaths.count == rhs.selectedPaths.count &&
        lhs.isStockVisible == rhs.isStockVisible &&
        lhs.zoomScale == rhs.zoomScale
    }

}
