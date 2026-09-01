//
//  ToolListView.swift
//  Stratum CNC
//
//  Created by Cristian Baluta on 25.08.2026.
//

import SwiftUI

struct ToolListView: View {

    let tools: [Tool]

    @Binding var selectedToolID: Tool.ID?

    var body: some View {
        List(tools, selection: $selectedToolID) { tool in
            Text(tool.displayName)
                .tag(tool.id)
        }
        .navigationTitle("Tool Library")
    }
}
