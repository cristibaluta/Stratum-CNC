//
//  MacrosListView.swift
//  Stratum CNC
//

import SwiftUI

/// The macro list. Shown in place of the toolpaths list when the MACROS tab is active.
struct MacrosListView: View {

    @ObservedObject var store: MacroStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $store.selectedMacroID) {
                ForEach(store.macros) { macro in
                    HStack(spacing: 8) {
                        Image(systemName: macro.systemImage)
                            .frame(width: 18)
                            .foregroundStyle(Color.accentColor)
                        Text(macro.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                    .tag(macro.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.selectedMacroID = macro.id
                    }
                }
            }
        }
    }
}
