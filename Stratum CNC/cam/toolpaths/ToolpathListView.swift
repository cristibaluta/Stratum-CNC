//
//  Toolpath.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 24.08.2026.
//

import SwiftUI

struct ToolpathListView: View {
    @ObservedObject var model: CAMStore
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
                var lastToolpath = model.toolpaths.last!
                lastToolpath.id = UUID()
                model.toolpaths += [lastToolpath]
            }
            Spacer()
        }
    }
}
