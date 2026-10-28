//
//  ToolpathListView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

struct PanelToolpaths: View {

    let toolpaths: [ToolpathData]
    let selectedID: UUID?
    var hiddenIDs: Set<UUID> = []

    var onSelect: ((UUID) -> Void)?
    var onToggleVisibility: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onAdd: (() -> Void)?
    /// Called once when a drag ends:
    var onMove: ((UUID, Int) -> Void)?

    @StateObject private var reorder = ToolpathReorderModel()

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
                VStack(alignment: .leading, spacing: ToolpathReorderModel.rowSpacing) {
                    ForEach(Array(toolpaths.enumerated()), id: \.element.id) { index, toolpath in
                        let isLifted = reorder.isLifted(toolpath.id)

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
                            .offset(y: reorder.yOffset(for: toolpath.id, at: index))
                            .zIndex(toolpath.id == reorder.draggingID ? 1 : 0)
                            // The lifted row follows the pointer, so it must not animate
                            .transaction { transaction in
                                if isLifted {
                                    transaction.animation = nil
                                }
                            }
                    }
                }
                .coordinateSpace(name: ToolpathReorderModel.listSpace)
                .onPreferenceChange(ToolpathRowHeightKey.self) { height in
                    if height > 0 {
                        reorder.rowHeight = height
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

    private func dragGesture(for toolpath: ToolpathData, at index: Int) -> some Gesture {
        // Measured in the list's own space: the row moves under the pointer while it is
        // dragged, so a translation in the row's space would feed back into itself.
        DragGesture(minimumDistance: 4, coordinateSpace: .named(ToolpathReorderModel.listSpace))
            .onChanged { value in
                reorder.dragChanged(id: toolpath.id,
                                    index: index,
                                    translation: value.translation.height,
                                    count: toolpaths.count)
            }
            .onEnded { value in
                reorder.dragEnded(id: toolpath.id,
                                  translation: value.translation.height,
                                  count: toolpaths.count) { id, target in
                    onMove?(id, target)
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
