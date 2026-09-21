//
//  ToolpathListView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

/// The compact list of toolpaths that sits under the objects panel (top-left).
/// One row per toolpath: eye (show/hide the generated result on the canvas),
/// name, delete. Clicking a row opens that toolpath's settings in the panel on
/// the right (see CAMView); clicking it again closes them.
/// Rows can be dragged to reorder.
struct ToolpathListView: View {

    @Binding var toolpaths: [ToolpathData]
    let selectedID: UUID?
    /// Toolpaths whose generated result is hidden on the canvas.
    var hiddenIDs: Set<UUID> = []

    var onSelect: ((UUID) -> Void)?
    var onToggleVisibility: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onAdd: (() -> Void)?

    @State private var draggedToolpath: ToolpathData?

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Toolpaths")
                    .font(.system(size: 13, weight: .bold))

                Spacer()

                Button {
                    onAdd?()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Add a toolpath")
            }

            if toolpaths.isEmpty {
                Text("No toolpaths")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(toolpaths) { toolpath in
                        toolpathRow(toolpath)
                            .onDrag {
                                draggedToolpath = toolpath
                                return NSItemProvider(object: toolpath.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text],
                                    delegate: ToolpathDropDelegate(target: toolpath,
                                                                   toolpaths: $toolpaths,
                                                                   draggedToolpath: $draggedToolpath))
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

    private func toolpathRow(_ toolpath: ToolpathData) -> some View {
        let isSelected = toolpath.id == selectedID
        let isHidden = hiddenIDs.contains(toolpath.id)

        return HStack(spacing: 4) {
            Button {
                onToggleVisibility?(toolpath.id)
            } label: {
                Image(systemName: isHidden ? "eye.slash" : "eye")
                    .frame(width: 20)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isHidden ? Color.secondary.opacity(0.5) : Color.secondary)
            .help(isHidden ? "Show on canvas" : "Hide from canvas")

            Button {
                onSelect?(toolpath.id)
            } label: {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(toolpath.name)
                            .lineLimit(1)
                        Text("\(toolpath.operation.kind.title) · \(toolpath.tool.name)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .opacity(isHidden ? 0.5 : 1)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                onDelete?(toolpath.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Delete toolpath")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
