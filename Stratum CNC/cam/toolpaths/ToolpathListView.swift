//
//  Toolpath.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

struct ToolpathListView: View {
    @ObservedObject var model: CAMModel
    @State private var draggedToolpath: ToolpathData?

    var body: some View {
        if model.toolpaths.isEmpty {
            emptyView
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {

                    ForEach($model.toolpaths) { $toolpath in
                        ToolpathCellView(toolpath: $toolpath)
                            .onDrag {
                                draggedToolpath = toolpath
                                return NSItemProvider(object: toolpath.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text],
                                    delegate: ToolpathDropDelegate(target: toolpath, toolpaths: $model.toolpaths, draggedToolpath: $draggedToolpath))
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
                var lastToolpath = model.toolpaths.last ?? ToolpathData(id: UUID(),
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
                model.toolpaths += [lastToolpath]
            }
            Spacer()
        }
    }
}
