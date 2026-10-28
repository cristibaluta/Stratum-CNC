//
//  ToolpathReorderModel.swift
//  Stratum CNC
//
//  Drag-to-reorder state and maths for `PanelToolpaths`.
//

import SwiftUI

/// Owns everything about dragging a row of the toolpath list: which row is lifted, which
/// slot it would drop into, how far it is from its own slot, and the commit/settle sequence.
/// The view only forwards the gesture and reads offsets back.
final class ToolpathReorderModel: ObservableObject, @unchecked Sendable {

    static let rowSpacing: CGFloat = 2
    static let listSpace = "toolpathList"

    /// The row being dragged, or settling into its new place after the drop.
    @Published private(set) var draggingID: UUID?
    /// Where the dragged row started, and the slot it would drop into right now.
    @Published private(set) var dragFrom: Int?
    @Published private(set) var dragTarget: Int?
    /// How far the dragged row is from its own slot.
    @Published private(set) var dragOffset: CGFloat = 0
    /// True from the first movement of the drag until the row has settled.
    @Published private(set) var isDragActive = false

    /// Measured from the rows. Not published: it only matters while dragging, and it is
    /// reported from inside a view update.
    var rowHeight: CGFloat = 38

    /// Distance between the tops of two neighbouring rows.
    var rowStride: CGFloat {
        rowHeight + Self.rowSpacing
    }

    // MARK: Queries

    /// True for the row that is lifted off the list and follows the pointer.
    func isLifted(_ id: UUID) -> Bool {
        isDragActive && id == draggingID
    }

    /// Vertical offset of a row while a drag is in progress: the dragged row follows the
    /// pointer, the rows it passes over step aside by one slot.
    func yOffset(for id: UUID, at index: Int) -> CGFloat {
        if id == draggingID {
            return dragOffset
        }
        guard let from = dragFrom, let target = dragTarget else {
            return 0
        }
        if from < target, index > from, index <= target {
            return -rowStride
        }
        if from > target, index >= target, index < from {
            return rowStride
        }
        return 0
    }

    // MARK: Gesture

    func dragChanged(id: UUID, index: Int, translation: CGFloat, count: Int) {
        if dragFrom == nil {
            // Ignore a new grab while another row is still settling
            guard draggingID == nil || draggingID == id else {
                return
            }
            draggingID = id
            dragFrom = index
            dragTarget = index
            isDragActive = true
        }
        guard let from = dragFrom, draggingID == id else {
            return
        }
        let travel = clampedTravel(translation, from: from, count: count)
        dragOffset = travel

        let slot = from + Int((travel / rowStride).rounded())
        let target = min(max(slot, 0), count - 1)
        if target != dragTarget {
            withAnimation(.easeInOut(duration: 0.15)) {
                dragTarget = target
            }
        }
    }

    /// Commits the drop through `onMove` (only when the slot changed), then lets the row
    /// glide into place.
    func dragEnded(id: UUID, translation: CGFloat, count: Int, onMove: (UUID, Int) -> Void) {
        guard let from = dragFrom, draggingID == id else {
            return
        }
        let travel = clampedTravel(translation, from: from, count: count)
        let target = dragTarget ?? from

        // Commit without animation. The row is re-offset by exactly the distance
        // its slot moved, and the rows that stepped aside lose their shift at the
        // same moment they take their new place, so nothing visibly jumps.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if target != from {
                onMove(id, target)
            }
            dragFrom = nil
            dragTarget = nil
            dragOffset = travel - CGFloat(target - from) * rowStride
        }

        // Then let the row glide into its slot
        DispatchQueue.main.async { [weak self] in
            withAnimation(.easeOut(duration: 0.18)) { [weak self] in
                self?.dragOffset = 0
                self?.isDragActive = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, !self.isDragActive else {
                    return
                }
                self.draggingID = nil
            }
        }
    }

    // MARK: Private

    /// The pointer's vertical travel, held so the row can't leave the list.
    private func clampedTravel(_ travel: CGFloat, from: Int, count: Int) -> CGFloat {
        let lowest = -CGFloat(from) * rowStride
        let highest = CGFloat(count - 1 - from) * rowStride
        return min(max(travel, lowest), highest)
    }
}
