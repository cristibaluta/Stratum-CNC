//
//  Toolpath.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

struct ToolpathListView: View {

    @Binding var toolpaths: [ToolpathData]
    /// The toolpath currently in "select shapes" mode, if any.
    var pickingToolpathID: UUID?
    var onTogglePicking: (UUID) -> Void = { _ in }
    /// Last generation result per toolpath id.
    var generations: [UUID: ToolpathGeneration] = [:]
    var onGenerate: (UUID) -> Void = { _ in }
    /// Toolpaths currently generating in the background.
    var generatingIDs: Set<UUID> = []

    @State private var draggedToolpath: ToolpathData?

    var body: some View {
        if toolpaths.isEmpty {
            emptyView
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {

                    ForEach($toolpaths) { $toolpath in
                        ToolpathCellView(toolpath: $toolpath,
                                         isPicking: pickingToolpathID == toolpath.id,
                                         onTogglePicking: { onTogglePicking(toolpath.id) },
                                         generation: generations[toolpath.id],
                                         isGenerating: generatingIDs.contains(toolpath.id),
                                         onGenerate: { onGenerate(toolpath.id) })
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
                .padding(8)
                addButton
            }
        }
    }

    private var emptyView: some View {
        VStack {
            Spacer()
            Text("No Toolpaths added yet.")
                .font(.headline)
                .foregroundColor(.secondary)
            addButton
            Spacer()
        }
    }

    private var addButton: some View {
        HStack {
            Spacer()
            Button("+ Add Toolpath") {
                var lastToolpath = toolpaths.last
                ?? ToolpathData(id: UUID(),
                                name: "First Toolpath",
                                tool: Tool(id: UUID(),
                                           name: "3.175mm",
                                           shankDiameter: 3.175,
                                           toolDiameter: 3.175,
                                           length: 12,
                                           type: .endMill,
                                           group: nil,
                                           tipAngle: nil,
                                           parameters: [:]),
                                startZ: 0,
                                endZ: -1,
                                contour: .outline,
                                ramping: RampingSettings(enabled: true,
                                                         type: .linear,
                                                         angle: 2,
                                                         length: 10),
                                feedRate: 0.1,
                                plungeRate: 0.1,
                                spindleRPM: 1200,
                                stepDown: 0.1,
                                stepOver: 0.1,
                                safeZ: 3)
                lastToolpath.id = UUID()
                // Copy the settings, not the shapes: the new toolpath starts with nothing selected
                lastToolpath.targets = []
                toolpaths += [lastToolpath]
            }
            Spacer()
        }
    }
}
