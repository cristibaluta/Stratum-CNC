//
//  ToolpathListView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

/// The toolpath list. Rows are reordered by dragging them; the
/// order is the order the toolpaths end up in the G-code program.
///
/// The reorder is done with a plain `DragGesture` on the row instead of `onDrag`/`onDrop`:
/// a drag-and-drop session never started from a row that holds a `Button`, was never
/// cancelled when dropped outside the list, and rewrote `camModel.toolpaths` (and so saved
/// the project) on every row the pointer crossed. Here the rows are only moved visually
/// while dragging, and the model is changed once, on release, through `onMove`.
struct PanelToolpaths: View {

    let toolpaths: [ToolpathData]
    let selectedID: UUID?
    var hiddenIDs: Set<UUID> = []

    var onSelect: ((UUID) -> Void)?
    var onToggleVisibility: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onAdd: (() -> Void)?
    /// Called once when a drag ends: the toolpath to move and the index it should have in
    /// the list afterwards.
    var onMove: ((UUID, Int) -> Void)?

    // MARK: Drag state

    /// The row being dragged, or settling into its new place after the drop.
    @State private var draggingID: UUID?
    /// Where the dragged row started, and the slot it would drop into right now.
    @State private var dragFrom: Int?
    @State private var dragTarget: Int?
    /// How far the dragged row is from its own slot.
    @State private var dragOffset: CGFloat = 0
    /// True from the first movement of the drag until the row has settled.
    @State private var isDragActive = false

    @State private var rowHeight: CGFloat = 38

    private static let rowSpacing: CGFloat = 2
    private static let listSpace = "toolpathList"

    /// Distance between the tops of two neighbouring rows.
    private var rowStride: CGFloat {
        rowHeight + Self.rowSpacing
    }

    private var canReorder: Bool {
        toolpaths.count > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InspectorHeader(title: "Toolpaths", addHelp: "Add a toolpath") {
                onAdd?()
            }

            Divider()

            if toolpaths.isEmpty {
                Text("No toolpaths")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                    .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: Self.rowSpacing) {
                    ForEach(Array(toolpaths.enumerated()), id: \.element.id) { index, toolpath in
                        let isLifted = isDragActive && toolpath.id == draggingID

                        toolpathRow(toolpath, at: index)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(key: ToolpathRowHeightKey.self,
                                                           value: proxy.size.height)
                                }
                            )
                            .background {
                                if isLifted {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(.thickMaterial)
                                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                                }
                            }
                            .offset(y: yOffset(for: toolpath, at: index))
                            .zIndex(toolpath.id == draggingID ? 1 : 0)
                            // The lifted row follows the pointer, so it must not animate
                            .transaction { transaction in
                                if isLifted {
                                    transaction.animation = nil
                                }
                            }
                    }
                }
                .coordinateSpace(name: Self.listSpace)
                .onPreferenceChange(ToolpathRowHeightKey.self) { height in
                    if height > 0 {
                        rowHeight = height
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Row

    private func toolpathRow(_ toolpath: ToolpathData, at index: Int) -> some View {
        let isSelected = toolpath.id == selectedID
        let isHidden = hiddenIDs.contains(toolpath.id)

        return HStack(spacing: 6) {
            if canReorder {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .frame(width: 12)
            }

            OperationIcon(kind: toolpath.operation.kind, size: 13)
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .opacity(isHidden ? 0.5 : 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(toolpath.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Text("\(toolpath.operation.kind.title) · \(toolpath.tool.name)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .opacity(isHidden ? 0.5 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)

            InspectorVisibilityButton(isVisible: !isHidden,
                                      showHelp: "Show on canvas",
                                      hideHelp: "Hide from canvas") {
                onToggleVisibility?(toolpath.id)
            }
        }
        .inspectorListRow(isSelected: isSelected)
        // The whole cell is the drag target and the select target. A tap and a drag on the
        // same view don't fight: the drag only starts after a few points of movement.
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect?(toolpath.id)
        }
        .gesture(dragGesture(for: toolpath, at: index))
        .contextMenu {
            Button(role: .destructive) {
                onDelete?(toolpath.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Reordering

    /// Vertical offset of a row while a drag is in progress: the dragged row follows the
    /// pointer, the rows it passes over step aside by one slot.
    private func yOffset(for toolpath: ToolpathData, at index: Int) -> CGFloat {
        if toolpath.id == draggingID {
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

    /// The pointer's vertical travel, held so the row can't leave the list.
    private func clampedTravel(_ travel: CGFloat, from: Int) -> CGFloat {
        let lowest = -CGFloat(from) * rowStride
        let highest = CGFloat(toolpaths.count - 1 - from) * rowStride
        return min(max(travel, lowest), highest)
    }

    private func dragGesture(for toolpath: ToolpathData, at index: Int) -> some Gesture {
        // Measured in the list's own space: the row moves under the pointer while it is
        // dragged, so a translation in the row's space would feed back into itself.
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.listSpace))
            .onChanged { value in
                if dragFrom == nil {
                    // Ignore a new grab while another row is still settling
                    guard draggingID == nil || draggingID == toolpath.id else {
                        return
                    }
                    draggingID = toolpath.id
                    dragFrom = index
                    dragTarget = index
                    isDragActive = true
                }
                guard let from = dragFrom, draggingID == toolpath.id else {
                    return
                }
                let travel = clampedTravel(value.translation.height, from: from)
                dragOffset = travel

                let slot = from + Int((travel / rowStride).rounded())
                let target = min(max(slot, 0), toolpaths.count - 1)
                if target != dragTarget {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        dragTarget = target
                    }
                }
            }
            .onEnded { value in
                guard let from = dragFrom, draggingID == toolpath.id else {
                    return
                }
                let travel = clampedTravel(value.translation.height, from: from)
                let target = dragTarget ?? from

                // Commit without animation. The row is re-offset by exactly the distance
                // its slot moved, and the rows that stepped aside lose their shift at the
                // same moment they take their new place, so nothing visibly jumps.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    if target != from {
                        onMove?(toolpath.id, target)
                    }
                    dragFrom = nil
                    dragTarget = nil
                    dragOffset = travel - CGFloat(target - from) * rowStride
                }

                // Then let the row glide into its slot
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.18)) {
                        dragOffset = 0
                        isDragActive = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        if !isDragActive {
                            draggingID = nil
                        }
                    }
                }
            }
    }
}

/// The height of a toolpath row, so the drag knows how far a slot is.
private struct ToolpathRowHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
