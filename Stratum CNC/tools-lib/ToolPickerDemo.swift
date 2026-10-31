//
//  ToolPickerDemo.swift
//  Stratum CNC
//
//  Demo of opening the tool library from a button and getting the picked
//  tool back. Picked values are printed to the debugger and used to fill
//  the fields below.
//

import SwiftUI

struct ToolPickerDemo: View {

    @StateObject private var store = ToolsStore()
    @State private var isPickerPresented = false

    // Fields populated from the picked tool.
    @State private var name = ""
    @State private var type = ""
    @State private var shankDiameter: Double = 0
    @State private var toolDiameter: Double = 0
    @State private var length: Double = 0

    var body: some View {
        Form {
            Section("Tool") {
                TextField("Name", text: $name)
                TextField("Type", text: $type)
                MeasurementField(title: "Shank Diameter", value: $shankDiameter, unit: "mm")
                MeasurementField(title: "Tool Diameter", value: $toolDiameter, unit: "mm")
                MeasurementField(title: "Length", value: $length, unit: "mm")

                Button("Pick Tool…") {
                    isPickerPresented = true
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isPickerPresented) {
            // Passing `onPick` is what makes the "Pick" button appear.
            ToolsSheet(store: store, onPick: { tool in
                print("Picked tool:")
                print("  id:            \(tool.id)")
                print("  name:          \(tool.name)")
                print("  type:          \(tool.type.displayName)")
                print("  group:         \(tool.group ?? "-")")
                print("  shankDiameter: \(tool.shankDiameter) mm")
                print("  toolDiameter:  \(tool.toolDiameter) mm")
                print("  length:        \(tool.length.map { "\($0) mm" } ?? "-")")
                print("  quantity:      \(tool.quantity)")
                print("  link:          \(tool.link ?? "-")")

                name = tool.name
                type = tool.type.displayName
                shankDiameter = tool.shankDiameter
                toolDiameter = tool.toolDiameter
                length = tool.length ?? 0
            })
        }
    }
}

#Preview {
    ToolPickerDemo()
        .frame(width: 500, height: 380)
}
