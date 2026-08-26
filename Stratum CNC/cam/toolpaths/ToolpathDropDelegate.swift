//
//  ToolpathDropDelegate.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

struct ToolpathDropDelegate: DropDelegate {
    let target: ToolpathData

    @Binding var toolpaths: [ToolpathData]
    @Binding var draggedToolpath: ToolpathData?

    func dropEntered(info: DropInfo) {
        guard let draggedToolpath else {
            return
        }

        guard draggedToolpath.id != target.id else {
            return
        }

        guard
            let fromIndex = toolpaths.firstIndex(
                where: { $0.id == draggedToolpath.id }
            ),
            let toIndex = toolpaths.firstIndex(
                where: { $0.id == target.id }
            )
        else {
            return
        }

        withAnimation(.easeInOut(duration: 0.15)) {
            toolpaths.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex
                    ? toIndex + 1
                    : toIndex
            )
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedToolpath = nil
        return true
    }
}
